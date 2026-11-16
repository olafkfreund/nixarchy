#!/usr/bin/env bash
# nixarchy pkg new <url> -- draft a derivation for software in no repository.
#
# Spliced into a writeShellApplication in modules/apps.nix; @nixpkgs@ becomes
# the generation's own nixpkgs, the same tree nixarchy-pkg-add parses against,
# and the shared lock helper (#1789) is spliced in at its own token below. The draft is built in the
# state directory and written to packages/ once, under the lock.
# nix-init does the drafting, headless. Its authors call the output a draft,
# and so does everything this prints: the builder, the dependencies and the
# licence are guesses for a person to review, not a package.
#
# Build before claiming (#581): the draft is built once, and a failure is
# reported as one -- with the draft KEPT, because a failed draft is still a
# better starting point than a blank file.
set -euo pipefail

nixpkgs='@nixpkgs@'

@writerLock@

usage() {
  echo "usage: nixarchy pkg new <url> [--rev REV] [--name NAME] [--update]"
  echo "  e.g. nixarchy pkg new https://github.com/someone/tool"
  echo
  echo "  Drafts a derivation into ~/.config/nixarchy/packages/<name>.nix"
  echo "  with nix-init, then builds it once and reports the result."
  echo "  The draft is yours to edit either way. --update redrafts over an"
  echo "  existing draft; without it, an existing draft is never overwritten."
  echo
  echo "  For software nixpkgs already carries, use: nixarchy pkg add <attr>"
}

url="" rev="" name="" update=false
while [ $# -gt 0 ]; do
  case "$1" in
    --rev)
      rev="${2:-}"
      [ -n "$rev" ] || { echo "--rev needs a value" >&2; exit 1; }
      shift 2
      ;;
    --name)
      name="${2:-}"
      [ -n "$name" ] || { echo "--name needs a value" >&2; exit 1; }
      shift 2
      ;;
    --update)
      update=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "nixarchy-pkg-new: unknown option '$1'" >&2
      exit 1
      ;;
    *)
      if [ -n "$url" ]; then
        echo "nixarchy-pkg-new: one URL at a time" >&2
        exit 1
      fi
      url="$1"
      shift
      ;;
  esac
done
[ -n "$url" ] || { usage >&2; exit 1; }
case "$url" in
  https://* | http://*) ;;
  *)
    echo "'$url' does not look like a URL this can fetch (expected https://...)." >&2
    echo "For something already in nixpkgs, use: nixarchy pkg add <attribute>" >&2
    exit 1
    ;;
esac

if [ -z "$name" ]; then
  name="${url%/}"
  name="${name##*/}"
  name="${name%.git}"
fi
# Same alphabet nixarchy-pkg-add accepts, and for the same reason: the name
# lands inside a nix expression and a file path.
case "$name" in
  "" | .* | *[!A-Za-z0-9_.-]*)
    echo "cannot make a package name out of '$name'; pass --name <name>." >&2
    exit 1
    ;;
esac

pkgdir="${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy/packages"
draft="$pkgdir/$name.nix"
# The default is a refusal, not a prompt: the existing draft may carry the
# user's edits, and silently overwriting them is the failure --update exists
# to make deliberate.
if [ -e "$draft" ] && [ "$update" != true ]; then
  echo "$draft already exists." >&2
  echo "Edit it, or redraft over it with: nixarchy pkg new --update $url" >&2
  exit 1
fi
# Drafted and built in the state directory; the real draft is untouched until
# the commit below, so a failed --update never trades an edited draft for nothing.
# One directory per run: two drafts of the same name must not share a work file.
mkdir -p "$nx_state/pkg-new"
workdir=$(mktemp -d -p "$nx_state/pkg-new")
work="$workdir/$name.nix"

# Globals, so the EXIT trap still sees them (CLAUDE.md §5). rmdir keeps a
# directory that still holds a failed --update's draft.
log=""
trap 'nx_unlock; rm -f "$log"; rmdir "$workdir" 2>/dev/null || :' EXIT

# Under the lock: refuse if a draft appeared while this was drafting, then
# write ours. nx_put keeps a symlinked or edited draft's file.
commit_draft() {
  nx_lock
  if [ -e "$draft" ] && [ "$update" != true ]; then
    nx_refuse "$draft appeared while this was drafting; nothing was written. Redraft over it with --update."
  fi
  mkdir -p "$pkgdir"
  nx_put "$work" "$draft"
}

echo "drafting  $draft"
initargs=(--headless --url "$url" -n "$nixpkgs")
if [ -n "$rev" ]; then
  initargs+=(--rev "$rev")
fi
if ! nix-init "${initargs[@]}" "$work" || [ ! -s "$work" ]; then
  echo
  echo "nix-init could not draft anything from $url." >&2
  echo "It understands release URLs and repositories on GitHub, GitLab," >&2
  echo "Codeberg, SourceHut, crates.io and PyPI." >&2
  rm -f "$work"
  [ ! -e "$draft" ] || echo "Your existing draft at $draft was left as it was." >&2
  exit 1
fi

log=$(mktemp)
try_build() {
  nix build --no-link --impure \
    --expr "(import $nixpkgs { }).callPackage $work { }" >"$log" 2>&1
}

printf 'building  %s ... ' "$name"
built=false
# Up to three rounds: nix-init leaves a placeholder where a hash cannot be
# known before the first build (cargoHash, vendorHash), and the failed build
# names the real one. Fill it in and go again; anything else is a real failure.
for _ in 1 2 3; do
  if try_build; then
    built=true
    break
  fi
  spec=$(sed -n 's/.*specified:[[:space:]]*\(sha256-[A-Za-z0-9+/=]*\).*/\1/p' "$log" | head -1)
  got=$(sed -n 's/.*got:[[:space:]]*\(sha256-[A-Za-z0-9+/=]*\).*/\1/p' "$log" | head -1)
  if [ -n "$spec" ] && [ -n "$got" ] && grep -qF "$spec" "$work"; then
    sed -i "s|$spec|$got|" "$work"
  else
    break
  fi
done

if [ "$built" != true ]; then
  echo "FAILED"
  echo
  tail -n 15 "$log" | sed 's/^/  | /'
  echo
  # A new draft is committed so it is where this says it is; an --update
  # leaves the real draft alone and keeps the redraft in the state directory.
  if [ "$update" = true ] && [ -e "$draft" ]; then
    kept=$work
    echo "The redraft did NOT build. Your existing draft at $draft was left as it was;"
    echo "the redraft is kept at"
  else
    commit_draft
    nx_unlock
    kept=$draft
    echo "The draft did NOT build. It is kept at"
  fi
  echo "  $kept"
  echo "because a failed draft is still a better starting point than a blank"
  echo "file. Edit it, then rebuild with:"
  echo "  nix build --impure --expr '(import $nixpkgs { }).callPackage $kept { }'"
  exit 1
fi
echo "ok"

appsfile="${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy/apps.nix"
entry="(callPackage ./packages/$name.nix { })"
commit_draft
# Consent rule (nixarchy-unfreeze's, via nixarchy-channel): only lines this
# project wrote get rewritten. The #@pkgs-end marker is nixarchy-pkg-add's own
# block, so inserting there -- commented out -- is within it; a file without
# the marker is the user's shape, and gets the edit printed instead.
if [ -f "$appsfile" ] && grep -qF "packages/$name.nix" "$appsfile"; then
  # An update, or a re-run after `nixarchy pkg undraft` left the file: the
  # line is already in the user's hands, so there is nothing to write.
  :
elif [ -f "$appsfile" ] && grep -q '#@pkgs-end' "$appsfile"; then
  tmp=$(mktemp -p "$nx_state")
  awk -v line="    # $entry  #@draft $name" '
    /#@pkgs-end/ && !done { print line; done = 1 }
    { print }
  ' "$appsfile" >"$tmp"
  nx_put "$tmp" "$appsfile"
  echo "added     $name to $appsfile (commented out)"
else
  echo "add it to your configuration yourself, e.g. in $appsfile:"
  echo "  environment.systemPackages = [ (pkgs.callPackage ./packages/$name.nix { }) ];"
fi
nx_unlock
echo
echo "This is a DRAFT: nix-init guessed the builder, the dependencies and the"
echo "licence. It builds, which is not the same as being right. Review it,"
echo "uncomment the line, then: nixarchy apply"
