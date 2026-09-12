#!/usr/bin/env bash
# What a Nix failure means, in the vocabulary of the files you wrote.
#
# Only 4.0% of respondents to the 2025 Nix community survey say they
# understand every Nix error message, and error messages were the
# second-highest improvement priority at 47.6%. Upstream's messages have to
# be general, which is a hard problem. This one only has to be right about
# the configuration nixarchy shipped, which is a much easier one.
#
# Reads an error -- from stdin, from a file, or from a command it runs -- and
# recognises it. It never rebuilds and never edits a file: the whole value is
# turning a trace that lands in lib/modules.nix into a sentence naming
# something the user typed, plus a snippet to paste. Same register as
# pkgs/doctor.sh, deliberately: one line of finding, then the paste-able
# block at the end.
#
# Exit 0 when it recognised something in reading mode, 2 when it did not --
# so a caller can tell whether the explainer had anything to add rather than
# printing an empty heading.
set -uo pipefail

bold=$(printf '\033[1m')
dim=$(printf '\033[2m')
warn=$(printf '\033[33m')
off=$(printf '\033[0m')

say() { printf '%s\n' "$*"; }
finding() { printf '  %s%s%s %s\n' "$2" "$1" "$off" "$3"; }
detail() { printf '    %s%s%s\n' "$dim" "$*" "$off"; }

# Every line that has to go into their configuration, collected as we go and
# printed together at the end -- a snippet to paste beats a list of prose
# instructions to translate. Same contract as doctor.sh's.
declare -a snippet=()
declare -a notes=()
found=0

usage() {
  cat <<'USAGE'
nixarchy explain -- what a Nix failure means

  nixarchy explain                     read the error from stdin
  nixarchy explain <file>              read it from a file
  nixarchy explain -- <command>...     run the command, explain what it printed

For example:

  sudo nixos-rebuild switch --flake . 2>&1 | nixarchy explain
  nixarchy explain -- nixos-rebuild build --flake .
USAGE
}

# ---- reading the error ---------------------------------------------------
# Three entry points because there are three moments someone reaches for
# this: mid-failure with the text still on screen, afterwards with a log, and
# ahead of time wrapping the command. The wrapper form passes the output
# through unchanged first -- swallowing the real error and replacing it with
# an interpretation is how an explainer becomes a thing to work around.
status=0
case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    if [ $# -eq 0 ]; then
      usage >&2
      exit 64
    fi
    # `|| status=$?` rather than a bare assignment: writeShellApplication
    # wraps this in `set -o errexit`, so capturing the output of a command
    # that fails -- the only kind this form is ever given -- killed the
    # script before it printed anything at all. Silently, with the exit
    # status of the wrapped command, which reads as the tool not being run.
    err=$("$@" 2>&1) || status=$?
    printf '%s\n' "$err"
    # A command that worked has nothing to explain, and a heading saying so
    # is noise on every successful rebuild someone wraps out of habit.
    if [ "$status" -eq 0 ]; then exit 0; fi
    say ""
    ;;
  "" | -)
    err=$(cat)
    ;;
  *)
    if [ ! -r "$1" ]; then
      say "nixarchy explain: cannot read $1" >&2
      exit 64
    fi
    err=$(cat -- "$1")
    ;;
esac

if [ -z "${err//[[:space:]]/}" ]; then
  say "nixarchy explain: nothing on the input to explain" >&2
  exit 64
fi

# Nix quotes a name four ways depending on version and on which subsystem is
# speaking: `foo' in the old spelling, 'foo' plainly, "foo", and the curly
# pair the module system uses. Two of those turn up in a single trace today.
# Every one is folded to a plain apostrophe here, once, rather than every
# pattern below carrying a four-way alternation -- and folded by literal byte
# substitution rather than a bracket expression, because a bracket expression
# over a three-byte character matches per byte under the C locale a build
# sandbox runs in, which is a silent wrong answer rather than an error.
err=$(
  printf '%s' "$err" |
    sed -e "s/$(printf '\342\200\230')/'/g" \
      -e "s/$(printf '\342\200\231')/'/g" \
      -e "s/\`/'/g"
)

has() { printf '%s' "$err" | grep -qF -- "$1"; }
hasre() { printf '%s' "$err" | grep -qE -- "$1"; }

between() { # <before> <after> -- the first quoted name after the marker
  printf '%s' "$err" | sed -n "s/.*$1'\([^']*\)'$2.*/\1/p" | head -1
}

say ""
say "${bold}What this error is${off}"
say ""

# ---- a file you have not git added --------------------------------------
# The single highest-value entry in the file. A flake sees only tracked or
# staged files, and an untracked one is reported as "does not exist" -- not
# as "untracked". Contributors to this repository lost three separate
# debugging sessions to it in one day, with the file plainly there in `ls`
# (AGENTS.md section 5). Newer Nix says "is not tracked by Git" and prints
# the fix; older Nix, and any path reaching evaluation through a store copy
# of the flake, still says "does not exist". Both spellings are matched
# because both are on machines running nixarchy today.
if
  has "is not tracked by Git" ||
    hasre "path '[^']*\.nix' does not exist"
then
  found=1
  missing=$(between "path " " does not exist")
  if [ -z "$missing" ]; then missing=$(between "Path " " in the repository"); fi
  finding "A file your flake imports is not in git" "$warn" "${missing:-the path the error names}"
  detail "Nix evaluates a flake from its git tree, so a file that is on disk and"
  detail "untracked does not exist as far as evaluation is concerned. That is why"
  detail "the error says 'does not exist' about a file you can ls."
  detail "Nothing is wrong with the file. It has never been added."
  snippet+=(
    "  # in your flake's directory:"
    "  git add ${missing:-<the file the error names>}"
    ""
    "  # 'git add', not 'git commit' -- staged is enough for evaluation."
  )
  notes+=("nixarchy-apply writes nixarchy-apps.nix into your flake root. If that is a git repo, the file needs adding the first time.")
fi

# ---- infinite recursion --------------------------------------------------
if has "infinite recursion encountered"; then
  found=1
  finding "Something is defined in terms of itself" "$warn" "infinite recursion"
  detail "Nix stopped following a definition that comes back round to itself. The"
  detail "trace points at where it gave up, which is rarely where the loop was"
  detail "closed -- look at what you most recently added, not at the frame shown."
  detail ""
  detail "Three shapes cause nearly all of them in a NixOS configuration:"
  detail "  - config.<option> read inside the definition of that same option"
  detail "  - a let binding that names itself: let pkgs = pkgs.foo; in ..."
  detail "  - an overlay using 'final' where it meant 'prev'"
  snippet+=(
    "  # An overlay reading final where it meant prev is the usual one:"
    "  nixpkgs.overlays = [ (final: prev: { foo = prev.foo.override { }; }) ];"
    "  #                                          ^^^^ prev, not final"
  )
fi

# ---- a module argument that is not there --------------------------------
# The distinguishing feature is that the trace names lib/modules.nix and
# nothing the user wrote, which is exactly the complaint in
# docs/manual/getting-started.md. A NixOS module argument cannot have a ?
# default: an argument absent from specialArgs resolves through _module.args
# rather than by the function default, so the module reads as correct and
# fails with 'attribute missing' two frames down.
if hasre "attribute '[^']*' missing"; then
  found=1
  attr=$(between "attribute " " missing")
  if has "_module.args" || has "modules.nix"; then
    finding "A module asked for an argument nothing passes it" "$warn" "${attr:-the attribute the error names}"
    detail "The trace lands in nixpkgs' own lib/modules.nix and names no file of"
    detail "yours, which is what makes this one unreadable. A module's arguments"
    detail "come from specialArgs and _module.args, never from the function's own"
    detail "default -- so { ${attr:-x} ? {} }: reads as correct and still fails here."
    snippet+=(
      "  # Pass it from the call site rather than defaulting it in the module:"
      "  _module.args.${attr:-yourArgument} = <value>;"
      ""
      "  # 'inputs' is the one people hit first. The flake nixarchy writes"
      "  # passes it already: specialArgs = { inherit inputs; };"
    )
  else
    finding "An attribute the configuration reads is not there" "$warn" "${attr:-the attribute the error names}"
    detail "Usually a package name that is not in this nixpkgs, or a spelling that"
    detail "changed between releases."
    snippet+=(
      "  # Check the name against the nixpkgs this machine actually follows:"
      "  nixarchy search ${attr:-<name>}"
    )
  fi
fi

# ---- an option that does not exist --------------------------------------
# Ordered after the untracked-file family on purpose: this message also
# contains the words "does not exist", and matching that loosely swallows
# the other one.
if hasre "The option '[^']*' does not exist"; then
  found=1
  opt=$(between "The option " " does not exist")
  finding "That option does not exist" "$warn" "${opt:-the option the error names}"
  detail "Either the name is misspelt, or it belongs to a module set this"
  detail "configuration does not import -- a home-manager option written into the"
  detail "system configuration is the common one, and it reads exactly like a"
  detail "typo. An option's own module has to be imported before its name is"
  detail "defined anywhere."
  snippet+=(
    "  # Every NixOS option, and every nixarchy one, in one picker:"
    "  nixarchy search ${opt:-<option>}"
  )
  case "$opt" in
    programs.nixarchy.*)
      notes+=("$opt is spelt like a nixarchy option and is not one -- 'nixarchy search programs.nixarchy' lists the whole surface.")
      ;;
    home | home.* | home-manager.*)
      notes+=("That name is home-manager's. It exists inside home-manager.users.<you> = { ... }, not in the system configuration.")
      ;;
    *) ;;
  esac
fi

# ---- two definitions of one option --------------------------------------
if hasre "has conflicting definition|conflicting definitions|has conflicting value"; then
  found=1
  opt=$(between "The option " " has conflicting")
  finding "Two places define the same option" "$warn" "${opt:-the option the error names}"
  detail "Nix will not guess which you meant, and the trace lands in"
  detail "lib/modules.nix rather than in either of the two files. Nixarchy sets"
  detail "its own defaults with lib.mkDefault, so a plain assignment of yours"
  detail "already wins over anything nixarchy ships -- if you are seeing this"
  detail "against a nixarchy option, the other definition is yours too."
  snippet+=(
    "  # Make one of the two yield, rather than raising both:"
    "  ${opt:-the.option} = lib.mkDefault <value>;   # this one gives way"
    "  ${opt:-the.option} = lib.mkForce   <value>;   # this one wins outright"
    ""
    "  # nixpkgs.config is NOT resolved by priority -- it is a free-form"
    "  # attribute set. Use programs.nixarchy.allowUnfree rather than writing"
    "  # nixpkgs.config.allowUnfree in two places."
  )
fi

# ---- two packages shipping the same file --------------------------------
# buildEnv's wording has changed across nixpkgs releases -- "collision
# between" in the spelling most people have seen, "conflicting subpath" in
# current nixpkgs -- and both are live on machines running nixarchy.
if hasre "collision between|conflicting subpath|colliding subpath"; then
  found=1
  finding "Two packages want to install the same file" "$warn" "a profile collision"
  detail "Nothing is broken. NixOS builds your packages into one directory of"
  detail "symlinks and two of them claim the same path -- almost always the same"
  detail "program twice, once from your systemPackages and once pulled in by"
  detail "something else, or one from nixpkgs and one from an overlay. The two"
  detail "store paths in the message name the culprits."
  snippet+=(
    "  # Keep both, and give the loser a worse priority:"
    "  environment.systemPackages = [ (lib.lowPrio pkgs.<the-one-to-yield>) ];"
    ""
    "  # Better where you can: install it once. Nixarchy does not install a"
    "  # second copy of something you already declare, and 'nixarchy doctor'"
    "  # lists what overlaps."
  )
fi

# ---- unfree, and insecure -----------------------------------------------
# Reads as a hard refusal and is a one-line opt-in. Nixarchy sets allowUnfree
# itself, so seeing it at all on a nixarchy machine usually means a second
# nixpkgs instance -- worth saying, because the obvious fix then goes in the
# wrong file and appears not to work.
# Both refusals now share the sentence "Refusing to evaluate package x in
# <file> because ..."; only the tail tells them apart, so matching the shared
# opening reports every insecure package as unfree.
if has "has an unfree license"; then
  found=1
  pkg=$(between "Refusing to evaluate package " " in ")
  finding "Nix is refusing an unfree package, and asking permission" "$warn" "${pkg:-the package the error names}"
  detail "A policy refusal, not a failure: the package is fine and the build never"
  detail "started. Nixarchy already sets nixpkgs.config.allowUnfree, so if you are"
  detail "seeing this on a nixarchy machine the package is coming from a second"
  detail "nixpkgs -- another flake input with its own instance, which your setting"
  detail "does not reach."
  snippet+=(
    "  programs.nixarchy.allowUnfree = true;   # this is the nixarchy default"
    ""
    "  # Set it there rather than writing nixpkgs.config.allowUnfree yourself:"
    "  # nixpkgs.config is a free-form attribute set, so two definitions of one"
    "  # key do not resolve by priority and yours may not be the one used."
  )
fi

if has "is marked as insecure"; then
  found=1
  pkg=$(between "Refusing to evaluate package " " in ")
  if [ -z "$pkg" ]; then pkg=$(between "Package " " in "); fi
  finding "Nix is refusing a package with a known vulnerability" "$warn" "${pkg:-the package the error names}"
  detail "Also a policy refusal. Someone recorded a CVE against this version and"
  detail "nixpkgs will not build it silently. The permitted list is by exact"
  detail "version string, so it stops applying the moment the package is updated"
  detail "-- which is the point of it."
  snippet+=(
    "  nixpkgs.config.permittedInsecurePackages = [ \"${pkg:-<name-version>}\" ];"
    ""
    "  # Copy the name and version exactly as the error printed them."
  )
fi

# ---- nothing matched -----------------------------------------------------
if [ "$found" -eq 0 ]; then
  say "  Nothing here matches a failure this explainer knows about."
  say ""
  detail "That is a gap worth reporting. It covers the failures a desktop user"
  detail "actually hits, and the list grows by people saying which one it missed:"
  detail "  https://github.com/olafkfreund/nixarchy/issues"
  say ""
  exit 2
fi

say ""
say "${bold}What to do${off}"
say ""
printf '%s\n' "${snippet[@]}"
say ""

if [ ${#notes[@]} -gt 0 ]; then
  say "${bold}Worth knowing${off}"
  for n in "${notes[@]}"; do
    say "  - $n"
  done
  say ""
fi

# The wrapper form reports the command's status, not the explainer's: a
# caller that ran a rebuild through this still needs to know the rebuild
# failed. Reading mode reports whether anything was recognised.
if [ "$status" -ne 0 ]; then exit "$status"; fi
exit 0
