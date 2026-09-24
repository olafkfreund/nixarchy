{ pkgs, doctor }:
# The doctor's plugin section (#959), driven against fixture homes.
#
# The failure it exists for cannot be reached by any VM here: it needs a user
# who cloned a plugin by hand BEFORE nixarchy shipped one at that id. No fixture
# machine has ever done that, and no installer produces it -- it is a state a
# person creates. So the state is faked, which is the only layer that can reach
# it at all.
#
# Five fixtures, and the important one is `newer`. A clone AHEAD of what we ship
# is somebody working, not a fault: on this maintainer's own machine one sat 28
# commits ahead, and a rule that moved it aside would have destroyed it. A check
# that only covered "stale" would have licensed exactly that rule.
pkgs.runCommand "nixarchy-doctor-plugins"
  {
    nativeBuildInputs = [
      pkgs.gnugrep
      pkgs.jq
    ];
  }
  ''
    # A home with a plugins directory, a manifest naming one shadowed id, and a
    # real directory carrying the given version. An empty version means "no
    # manifest.json at all", which is the not-a-plugin-of-ours case.
    mk() { # mk <name> <id> <ourver> <yourver>
      d=fix/$1/omarchy/plugins
      mkdir -p "$d/$2"
      printf '!%s\t%s\n' "$2" "$3" > "$d/.nixarchy-managed"
      if [ -n "$4" ]; then
        printf '{"id":"%s","version":"%s"}\n' "$2" "$4" > "$d/$2/manifest.json"
      fi
    }

    mk stale   nixarchy.herdr 0.3.0 0.2.0
    mk newer   nixarchy.herdr 0.2.0 0.3.0
    mk same    nixarchy.herdr 0.3.0 0.3.0
    mk unknown nixarchy.herdr 0.3.0 ""

    # A home nixarchy manages with nothing shadowed: a manifest of plain ids.
    mkdir -p fix/clean/omarchy/plugins/nixarchy.herdr
    echo "nixarchy.herdr" > fix/clean/omarchy/plugins/.nixarchy-managed

    # And a machine that has never had nixarchy: no manifest at all. This one is
    # the reason the section is guarded rather than unconditional -- doctor's
    # primary reader is a person evaluating nixarchy before installing it, and
    # showing them a section about plugins they do not have is worse than
    # showing them nothing.
    mkdir -p fix/virgin

    run() { # run <name>
      ( XDG_CONFIG_HOME=$PWD/fix/$1 ${doctor}/bin/nixarchy-doctor 2>&1 || true ) > out.$1
      echo "=== $1"; cat out.$1
    }
    for f in stale newer same unknown clean virgin; do run $f; done | tee transcript

    fail() { echo "FAIL: $1" >&2; exit 1; }

    # The finding. Both versions named: a message that says "out of date" and
    # not WHICH is which cannot be acted on without going to look.
    grep -q '0\.2\.0' out.stale || fail "stale: does not name the version the machine runs"
    grep -q '0\.3\.0' out.stale || fail "stale: does not name the version nixarchy ships"
    grep -q 'mv .*nixarchy.herdr' out.stale || fail "stale: no way out is offered"

    # Newer is NOT a finding, and must not offer to move anything aside.
    grep -q '0\.3\.0' out.newer || fail "newer: does not name the user's version"
    ! grep -q 'mv .*nixarchy.herdr' out.newer \
      || fail "newer: offered to move aside a clone that is AHEAD of ours"

    # Same version is the latent case: correct today, silently stale at the
    # next pin bump. It must say so and must not offer a fix.
    grep -qi 'same version\|both 0\.3\.0' out.same || fail "same: does not say they match"
    ! grep -q 'mv .*nixarchy.herdr' out.same || fail "same: offered a fix for a machine that is fine"

    # No manifest.json in the user's directory: we cannot compare, and must not
    # pretend to. It still says the directory is standing in for ours.
    grep -qi 'not managing it\|stands in' out.unknown \
      || fail "unknown: silent about a directory shadowing a declared plugin"

    # Nothing shadowed, and never-had-nixarchy: the section says NOTHING.
    ! grep -qi 'Plugins of yours' out.clean || fail "clean: printed a plugin section with nothing shadowed"
    ! grep -qi 'Plugins of yours' out.virgin || fail "virgin: printed a plugin section on a machine with no manifest"

    mkdir -p $out
    cp transcript $out/
    echo "doctor plugins: 6 fixtures, all asserted"
  ''
