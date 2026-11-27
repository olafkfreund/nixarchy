{ pkgs, ... }:
# The "files this port patches that upstream changed" section of every Omarchy
# bump PR.
#
# The script derives that set from six statements the repo already makes --
# pkgs/omarchy/nix-bin/*, substituteInPlace paths in pkgs/omarchy/default.nix,
# sed -i and ${src}/ paths in the same file, seed_dir in modules/home.nix,
# and +++ b/PATH lines in pkgs/omarchy/*.patch -- rather
# than from a list somebody keeps by hand. Which trades one failure for
# another: a hand-kept list goes stale loudly the first time somebody reads it,
# while six derivations go stale in perfect silence and report "none of the 167
# files upstream changed is one we touch" forever.
#
# So this runs the real greps against the real repo files, not fixtures of
# them. If pkgs/omarchy/default.nix stops writing `substituteInPlace
# $out/share/omarchy/...`, or the bins move out of nix-bin/, this goes red
# here instead of going quiet in a PR body nobody can check.
#
# The changed-file list is a fixture, because that half comes from the network.
let
  # The real 4.0.1 -> 4.0.2 compare, trimmed: two bins this port replaces with
  # a stub, one it patches, one it edits only with `sed -i`, one file it reads
  # straight out of the source, one package list it reads at evaluation (the
  # PDF viewer follows it, #1736), one seeded config file, and three upstream
  # changes that need no thought here.
  changed = builtins.toFile "changed.txt" ''
    bin/omarchy-plymouth-set
    bin/omarchy-refresh-sddm
    bin/omarchy-version-channel
    bin/omarchy-theme-bg-next
    bin/omarchy-plugin-clone
    config/hypr/xdph.conf
    default/plymouth/omarchy.script
    install/omarchy-base.packages
    themes/catppuccin/alacritty.toml
    README.md
  '';

  patchChanged = builtins.toFile "patch-changed.txt" ''
    bin/omarchy-theme-bg-next
  '';

  attrib = builtins.toFile "attrib.txt" ''
    bin/omarchy-plymouth-set	Merge pull request #8934 from ErikMelton/security/plymouth-publication-race
    bin/omarchy-refresh-sddm	Merge pull request #8934 from ErikMelton/security/plymouth-publication-race
  '';
in
pkgs.runCommand "nixarchy-patched-files"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      findutils
      gnugrep
      gnused
      gawk
    ];
  }
  ''
    script=${../.github/scripts/omarchy-patched-files.sh}
    fail=0

    # The real statements, in the layout the script expects to find them in.
    mkdir -p root/pkgs/omarchy root/modules
    cp -r ${../pkgs/omarchy/nix-bin} root/pkgs/omarchy/nix-bin
    cp ${../pkgs/omarchy/default.nix} root/pkgs/omarchy/default.nix
    cp ${../pkgs/omarchy}/*.patch root/pkgs/omarchy/
    cp ${../modules/home.nix} root/modules/home.nix
    chmod -R u+w root

    report=$(bash "$script" ${changed} root ${attrib} v4.0.1 v4.0.2)

    # One line per source of "this port has its hands on it", so a single grep
    # that has stopped matching cannot hide behind the other three.
    for want in bin/omarchy-plymouth-set bin/omarchy-refresh-sddm \
      bin/omarchy-version-channel bin/omarchy-plugin-clone config/hypr/xdph.conf \
      default/plymouth/omarchy.script; do
      <<<"$report" grep -q "$want" || {
        echo "patched files: $want is a file this port touches and is missing" >&2
        fail=1
      }
    done

    # And each with the right reason, because the reason is what tells a
    # reviewer whether upstream's fix reaches a machine here at all.
    echo "$report" | grep 'omarchy-plymouth-set' | grep -q 'nix-bin' || {
      echo "patched files: a stubbed bin is not described as stubbed" >&2
      fail=1
    }
    # The one reached only by `sed -i`, through a variable on another line.
    echo "$report" | grep 'omarchy-plugin-clone' | grep -q 'sed -i' || {
      echo "patched files: a file edited only by sed -i is not described as such" >&2
      fail=1
    }
    echo "$report" | grep 'xdph.conf' | grep -q 'seeded' || {
      echo "patched files: a seeded config file is not described as seeded" >&2
      fail=1
    }

    # A patch-only path must join the derived set, with its own changed list
    # so the main fixture's exact count remains a useful assertion.
    cp -r root patch-root
    printf '%s\n' '--- a/bin/omarchy-theme-bg-next' '+++ b/bin/omarchy-theme-bg-next' \
      > patch-root/pkgs/omarchy/fixture.patch
    cp --no-preserve=mode ${patchChanged} patch-changed.txt
    patch_paths=$(grep '^+++ b/' root/pkgs/omarchy/1625-no-mise.patch | sed 's|^+++ b/||')
    printf '%s\n' "$patch_paths" >> patch-changed.txt
    patch_report=$(bash "$script" patch-changed.txt patch-root ${attrib} v4.0.1 v4.0.2)
    <<<"$patch_report" grep -q '^10 files changed' || {
      echo "patched files: patch fixture changed-file total is wrong" >&2
      fail=1
    }
    <<<"$patch_report" grep -q 'omarchy-theme-bg-next.*pkgs/omarchy/.*patch' || {
      echo "patched files: a patch-only path was not reported as patched" >&2
      fail=1
    }
    while IFS= read -r path; do
      <<<"$patch_report" grep -Fq "\`$path\` — patched by \`pkgs/omarchy/*.patch\`" || {
        echo "patched files: $path was not reported as patched by the new patch" >&2
        fail=1
      }
    done <<<"$patch_paths"

    # The other half, and the one that decides whether this is readable at
    # all. `substituteInPlace $out/share/omarchy/bin/$f` inside a loop would
    # derive the prefix `bin/`, which matches every bin upstream touched --
    # 167 changed files would come back as a hundred "worth a second look",
    # which is the same as none.
    for noise in bin/omarchy-theme-bg-next \
      themes/catppuccin/alacritty.toml README.md; do
      <<<"$report" grep -q "$noise" && {
        echo "patched files: $noise is untouched here and was reported anyway" >&2
        fail=1
      }
    done

    # The count in the prose is the count in the list.
    <<<"$report" grep -q '^10 files changed' || {
      echo "patched files: the changed-file total is wrong or missing" >&2
      fail=1
    }

    # Attribution, which is the whole reason to read this section: a security
    # fix landing upstream in a file this port replaces with a stub.
    <<<"$report" grep -q 'plymouth-publication-race' || {
      echo "patched files: the upstream commit subject was not rendered" >&2
      fail=1
    }

    # --list is what the workflow asks before it goes to the network.
    listed=$(bash "$script" --list ${changed} root)
    [ "$(echo "$listed" | wc -l)" = 7 ] || {
      echo "patched files: --list printed $(echo "$listed" | wc -l) paths, expected 7" >&2
      echo "$listed" >&2
      fail=1
    }
    <<<"$listed" grep -q ' ' && {
      echo "patched files: --list printed prose, not bare paths" >&2
      fail=1
    }

    # The guard. Six derivations against files that move; if any finds
    # nothing, the intersection is empty for a reason that has nothing to do
    # with the release, and an empty intersection reads as "nothing to see".
    mkdir -p empty/pkgs/omarchy/nix-bin empty/modules
    touch empty/pkgs/omarchy/default.nix empty/modules/home.nix
    if bash "$script" ${changed} empty > empty.out 2>&1; then
      echo "patched files: a repo stating none of the six was accepted" >&2
      cat empty.out >&2
      fail=1
    else
      grep -q 'Refusing to report' empty.out || {
        echo "patched files: the empty-derivation guard fired without saying why" >&2
        cat empty.out >&2
        fail=1
      }
    fi

    [ "$fail" -eq 0 ] || {
      echo >&2
      echo "What the report actually said:" >&2
      echo "$report" >&2
      exit 1
    }

    echo "the intersection names every file this port replaces, patches, reads"
    echo "or seeds, names nothing else, and refuses to report an empty"
    echo "intersection when it is the derivation that broke"
    touch $out
  ''
