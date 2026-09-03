{ pkgs, ... }:
# The release notes, against a repository with a known answer.
#
# `.github/scripts/release-notes.sh` derives what a release changed by grepping
# for four shapes: the Omarchy pin in flake.nix, `version = "..."` under
# pkgs/apps, `= lib.mkDefault ...` under modules, and the option set Nix
# evaluates. Each of those can stop matching -- someone reformats a line,
# renames a file, moves an option -- and when one does, the script produces a
# release note that reads calm and says nothing. That is the same failure
# tests/package-delta.nix was written for, one level up and with more surface.
#
# So: a fixture git repository with two revisions whose diff is known, driven
# through the real script. The option maps are handed over rather than
# evaluated, and the two GitHub fetches are simply allowed to fail, because a
# sandboxed derivation has no network and cannot evaluate a flake -- and a
# failed fetch is itself one of the things asserted on here, since the script's
# contract is that it says so out loud rather than printing an empty section.
#
# The four negative cases at the bottom are the point of the whole file: a
# scan that has stopped matching must exit non-zero, not report calm.
let
  # A default that moved, one option gained, one lost. Shaped exactly like the
  # `nix eval` in the script: every value is a JSON document in a string.
  optsFrom = builtins.toFile "opts-from.json" (
    builtins.toJSON {
      "programs.nixarchy.enable" = "false";
      "programs.nixarchy.theme" = "\"tokyo-night\"";
      "programs.nixarchy.retired" = "true";
    }
  );

  optsTo = builtins.toFile "opts-to.json" (
    builtins.toJSON {
      "programs.nixarchy.enable" = "false";
      "programs.nixarchy.theme" = "\"catppuccin\"";
      "programs.nixarchy.services.rdp.enable" = "false";
    }
  );

  # The same map twice: nothing changed, and the script must say that in
  # words rather than by leaving the section out.
  optsSame = optsFrom;
in
pkgs.runCommand "nixarchy-release-notes"
  {
    nativeBuildInputs = with pkgs; [
      bash
      git
      curl
      jq
      gawk
      gnugrep
      gnused
      coreutils
    ];
  }
  ''
    export HOME=$TMPDIR
    export GIT_CONFIG_GLOBAL=$TMPDIR/gitconfig
    export GIT_CONFIG_SYSTEM=/dev/null
    notes=${../.github/scripts/release-notes.sh}
    export NIXARCHY_PACKAGE_DELTA=${../.github/scripts/omarchy-package-delta.sh}
    export NIXARCHY_OPTIONS_FROM=${optsFrom}
    export NIXARCHY_OPTIONS_TO=${optsTo}
    fail=0

    git init -q -b main "$TMPDIR/repo"
    cd "$TMPDIR/repo"
    git config user.email fixture@example.invalid
    git config user.name fixture

    commit() { git add -A && git commit -q -m "$1"; }

    # --- the release being left behind ---
    mkdir -p modules pkgs/apps installer docs
    cat > flake.nix <<'EOF'
    {
      inputs.omarchy.url = "github:basecamp/omarchy/v4.0.1";
      outputs = { ... }: { };
    }
    EOF
    cat > modules/nixos.nix <<'EOF'
    {
      services.printing.enable = lib.mkDefault true;
      services.avahi.enable = lib.mkDefault true;
    }
    EOF
    printf '  version = "0.3.1";\n' > pkgs/apps/once.nix
    printf '  version = "0.3.2";\n' > pkgs/apps/ttfx.nix
    commit "The release before this one"
    git tag v-old

    # --- three commits, three different corners of the tree ---
    echo 'ask() { :; }' > installer/wizard.sh
    commit "The installer asks one more question (#900)"

    echo 'a manual page' > docs/manual.md
    commit "Docs: the page that was missing (#901)"

    # And the release itself: an upstream bump, a pinned version, and a NixOS
    # default turned off -- the shape of the real v4.0.2-1.
    sed -i 's|omarchy/v4.0.1|omarchy/v4.0.2|' flake.nix
    sed -i 's|0.3.1|0.4.0|' pkgs/apps/once.nix
    cat >> modules/nixos.nix <<'EOF'
    {
      services.printing.browsed.enable = lib.mkDefault false;
    }
    EOF
    commit "Omarchy 4.0.2, and a daemon that should not have been running (#902)"

    report=$(bash "$notes" v-old main) || {
      echo "release-notes: the script failed on the fixture repository" >&2
      exit 1
    }

    has() { # pattern, what it is about
      echo "$report" | grep -qF "$1" || {
        echo "release-notes: missing $2" >&2
        echo "  looked for: $1" >&2
        fail=1
      }
    }

    # 1. What this release is. Both tags named, in the right direction.
    has 'up from `v4.0.1`' "the Omarchy version this release moved on from"
    has 'Omarchy `v4.0.2`' "the Omarchy version this release vendors"

    # A sandbox has no network, and the contract for that is a loud line rather
    # than a quiet absence. This is the case that would otherwise let a release
    # note say nothing about a security bump and look complete doing it.
    has 'package lists could not be fetched' \
      "the notice that the upstream package delta is missing"
    has 'could not be asked which files upstream changed' \
      "the notice that the seeded-config comparison is missing"

    # 2. Configuration. The default that moved comes first and carries both
    # values; a machine that never mentioned it follows the new one.
    has '`programs.nixarchy.theme`: `"tokyo-night"` → `"catppuccin"`' \
      "the option whose default changed"
    has '`programs.nixarchy.services.rdp.enable` (default `false`)' \
      "the added option and its default"
    has '`programs.nixarchy.retired`' "the removed option"

    # An option that did not move must appear in none of the three lists.
    echo "$report" | grep -q 'programs.nixarchy.enable' && {
      echo "release-notes: an unchanged option was reported as a change" >&2
      fail=1
    }

    # The half the option walk cannot see: a NixOS default this port sets.
    # This is #201's cups-browsed, which is not an option of ours at all.
    has 'now `services.printing.browsed.enable = lib.mkDefault false;`' \
      "the NixOS default this release turned off"
    has 'in `modules/nixos.nix`' "the module a changed default lives in"

    # 3. Packages. The one that moved, and not the one that did not.
    has '`once` 0.3.1 → 0.4.0' "the pinned package whose version moved"
    echo "$report" | grep -q 'ttfx 0.3.2 →' && {
      echo "release-notes: an unmoved pin was reported as having moved" >&2
      fail=1
    }

    # 4. The log, grouped by where each change landed. Buckets are decided by
    # path, so this asserts the subject lands under the right heading rather
    # than merely appearing somewhere.
    installers=$(echo "$report" | sed -n '/^### Installing/,/^### /p')
    echo "$installers" | grep -qF "The installer asks one more question (#900)" || {
      echo "release-notes: the installer commit is not under the installer heading" >&2
      fail=1
    }
    docsbucket=$(echo "$report" | sed -n '/^### Documentation/,/^### /p')
    echo "$docsbucket" | grep -qF "Docs: the page that was missing (#901)" || {
      echo "release-notes: the docs commit is not under the documentation heading" >&2
      fail=1
    }
    has '3 changes since `v-old`' "the count of changes"

    # Silence has to mean silence: two identical option maps produce a
    # sentence, not an absent section.
    quiet=$(NIXARCHY_OPTIONS_TO=${optsSame} bash "$notes" v-old main)
    echo "$quiet" | grep -q 'No option was added, removed or given a different' || {
      echo "release-notes: an unchanged option set produced no sentence saying so" >&2
      fail=1
    }
    # ...except the NixOS default, which did move in this fixture and must
    # still be reported when nothing else did.
    echo "$quiet" | grep -q 'services.printing.browsed.enable' || {
      echo "release-notes: a changed NixOS default vanished when no option changed" >&2
      fail=1
    }

    # --- the four scans, broken on purpose ------------------------------------
    #
    # Each of these is a shape the script greps for. When one stops matching,
    # "nothing changed" is the wrong answer and a non-zero exit is the right
    # one. This is the whole reason the file exists.
    rots() { # branch, description, what the script must say
      git checkout -q -b "$1" main
    }

    expect_refusal() { # description, expected substring
      refused=$(bash "$notes" v-old "$2" 2>&1) && {
        echo "release-notes: $1 -- the script reported success instead of refusing" >&2
        echo "$refused" >&2
        fail=1
        return
      }
      echo "$refused" | grep -q "$3" || {
        echo "release-notes: $1 -- refused, but not with the reason expected" >&2
        echo "  looked for: $3" >&2
        echo "$refused" >&2
        fail=1
      }
    }

    rots rot-pin
    sed -i 's|github:basecamp/omarchy/v4.0.2|path:/somewhere/else|' flake.nix
    commit "The Omarchy pin no longer looks like a github ref"
    expect_refusal "an unreadable Omarchy pin" rot-pin \
      "the scan for the vendored version has stopped matching"

    git checkout -q main
    rots rot-versions
    sed -i 's|version = |theVersion: |' pkgs/apps/*.nix
    commit "Every pinned version is written another way"
    expect_refusal "unreadable pinned versions" rot-versions \
      "the scan for this repo's pinned versions has stopped matching"

    git checkout -q main
    rots rot-mkdefault
    sed -i 's|lib.mkDefault |defaultTo |g' modules/nixos.nix
    commit "mkDefault is spelled some other way now"
    expect_refusal "an unreadable set of NixOS defaults" rot-mkdefault \
      "the scan for the defaults this port sets has stopped matching"

    git checkout -q main
    empty=$(mktemp)
    echo '{}' > "$empty"
    refused=$(NIXARCHY_OPTIONS_TO="$empty" bash "$notes" v-old main 2>&1) && {
      echo "release-notes: an empty option set was reported as no change" >&2
      echo "$refused" >&2
      fail=1
    }
    echo "$refused" | grep -q 'has stopped finding options' || {
      echo "release-notes: an empty option set refused, but not for that reason" >&2
      echo "$refused" >&2
      fail=1
    }

    [ "$fail" -eq 0 ] || {
      echo >&2
      echo "What the notes actually said:" >&2
      echo "$report" >&2
      exit 1
    }

    echo "the release notes name what moved, in the right section,"
    echo "and refuse rather than report calm when a scan stops matching"
    touch $out
  ''
