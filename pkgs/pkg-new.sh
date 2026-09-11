#!/usr/bin/env bash
# nixarchy pkg new <url> -- draft a derivation for software in no repository.
#
# Spliced into a writeShellApplication in modules/apps.nix; @nixpkgs@ becomes
# the generation's own nixpkgs, the same tree nixarchy-pkg-add parses against.
# nix-init does the drafting, headless. Its authors call the output a draft,
# and so does everything this prints: the builder, the dependencies and the
# licence are guesses for a person to review, not a package.
#
# Build before claiming (#581): the draft is built once, and a failure is
# reported as one -- with the draft KEPT, because a failed draft is still a
# better starting point than a blank file.
set -euo pipefail

nixpkgs='@nixpkgs@'

usage() {
  echo "usage: nixarchy pkg new <url> [--rev REV] [--name NAME]"
  echo "  e.g. nixarchy pkg new https://github.com/someone/tool"
  echo
  echo "  Drafts a derivation into ~/.config/nixarchy/packages/<name>.nix"
  echo "  with nix-init, then builds it once and reports the result."
  echo "  The draft is yours to edit either way."
  echo
  echo "  For software nixpkgs already carries, use: nixarchy pkg add <attr>"
}

url="" rev="" name=""
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
if [ -e "$draft" ]; then
  echo "$draft already exists." >&2
  echo "Edit it, or remove it and run this again to redraft." >&2
  exit 1
fi
mkdir -p "$pkgdir"

echo "drafting  $draft"
initargs=(--headless --url "$url" -n "$nixpkgs")
if [ -n "$rev" ]; then
  initargs+=(--rev "$rev")
fi
if ! nix-init "${initargs[@]}" "$draft" || [ ! -s "$draft" ]; then
  echo
  echo "nix-init could not draft anything from $url." >&2
  echo "It understands release URLs and repositories on GitHub, GitLab," >&2
  echo "Codeberg, SourceHut, crates.io and PyPI." >&2
  # A failed nix-init can leave an empty file behind; an empty draft is not
  # a starting point, it is a landmine for the next run's already-exists check.
  rm -f "$draft"
  exit 1
fi

log=$(mktemp)
trap 'rm -f "$log"' EXIT
try_build() {
  nix build --no-link --impure \
    --expr "(import $nixpkgs { }).callPackage $draft { }" >"$log" 2>&1
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
  if [ -n "$spec" ] && [ -n "$got" ] && grep -qF "$spec" "$draft"; then
    sed -i "s|$spec|$got|" "$draft"
  else
    break
  fi
done

if [ "$built" != true ]; then
  echo "FAILED"
  echo
  tail -n 15 "$log" | sed 's/^/  | /'
  echo
  echo "The draft did NOT build. It is kept at"
  echo "  $draft"
  echo "because a failed draft is still a better starting point than a blank"
  echo "file. Edit it, then rebuild with:"
  echo "  nix build --impure --expr '(import $nixpkgs { }).callPackage $draft { }'"
  exit 1
fi
echo "ok"

appsfile="${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy/apps.nix"
entry="(callPackage ./packages/$name.nix { })"
# Consent rule (nixarchy-unfreeze's, via nixarchy-channel): only lines this
# project wrote get rewritten. The #@pkgs-end marker is nixarchy-pkg-add's own
# block, so inserting there -- commented out -- is within it; a file without
# the marker is the user's shape, and gets the edit printed instead.
if [ -f "$appsfile" ] && grep -q '#@pkgs-end' "$appsfile" && ! grep -qF "packages/$name.nix" "$appsfile"; then
  tmp=$(mktemp)
  awk -v line="    # $entry  #@draft $name" '
    /#@pkgs-end/ && !done { print line; done = 1 }
    { print }
  ' "$appsfile" >"$tmp" && mv "$tmp" "$appsfile"
  echo "added     $name to $appsfile (commented out)"
else
  echo "add it to your configuration yourself, e.g. in $appsfile:"
  echo "  environment.systemPackages = [ (pkgs.callPackage ./packages/$name.nix { }) ];"
fi
echo
echo "This is a DRAFT: nix-init guessed the builder, the dependencies and the"
echo "licence. It builds, which is not the same as being right. Review it,"
echo "uncomment the line, then: nixarchy apply"
