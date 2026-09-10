{ pkgs }:
# The gate that decides whether a pull request runs the install VM.
#
# It is worth a check because the two directions cost very differently. A false
# RUN wastes 26-46 minutes on one serialised slot. A false SKIP merges a
# broken installer with nothing having looked at it -- and that is exactly
# what #123 was: hosts/<name>/ layout changed module ORDER, which changed the
# system path hash, and the installer then tried to build 517 derivations
# offline. No file anyone would have called "installer" was touched.
#
# So the script stays a denylist, and this asserts both questions it answers:
# build.yml's "can this change anything Nix builds?" and install-check.yml's
# narrower "can this change an INSTALL?".
pkgs.runCommand "nixarchy-install-gate"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
    ];
    gate = ../.github/scripts/pr-touches-build.sh;
  }
  ''
    fails=0
    # $2 is the mode: empty for the build question, --install for the narrow
    # one. Passing the file list on stdin is the script's own test seam.
    t() {
      got=$(printf '%s\n' "$3" | bash $gate $2 - 2>/dev/null || true)
      if [ "$got" = "$4" ]; then echo "  ok      $1"
      else echo "  FAILED  $1: got '$got', wanted '$4'"; fails=$((fails + 1)); fi
    }

    echo "the install question:"
    # The saving. A check the install job does not build cannot change an
    # install, and this one cost a 37-minute VM on the day it was added.
    t "an unrelated check does not run the VM" --install "tests/substitutable.nix" false
    t "docs do not"                            --install "docs/manual/android.md" false
    # The three the job actually builds, and the two files they import. These
    # are the entries whose absence would make the saving unsafe.
    t "tests/install.nix does"                 --install "tests/install.nix" true
    t "tests/free-space.nix does"              --install "tests/free-space.nix" true
    t "tests/installer-refusal.nix does"       --install "tests/installer-refusal.nix" true
    t "the shared hardware fixture does"       --install "tests/hardware-configuration.nix" true
    t "the shared instrumentation does"        --install "tests/test-instrumentation.nix" true
    # #123's lesson: relevance is not a directory name.
    t "a module does"                          --install "modules/nixos.nix" true
    t "installer code does"                    --install "installer/install.sh" true
    t "a data row does"                        --install "data/apps.nix" true
    # README is deliberately NOT excluded: build.yml derives counts from data/
    # and greps README for them, so a README-only edit can legitimately fail.
    t "README does"                            --install "README.md" true

    echo "the build question, unchanged:"
    t "an unrelated check still builds"        "" "tests/substitutable.nix" true
    t "docs still do not"                      "" "docs/manual/android.md" false
    t "the gate itself always does"            "" ".github/scripts/pr-touches-build.sh" true
    t "install-check.yml always does"          "" ".github/workflows/install-check.yml" true

    echo "fails safe:"
    # An empty list means the question could not be answered -- a paginated API
    # call that returned nothing, a renamed field. Unknown must mean run
    # everything, because the cheap answer skips every build.
    t "an empty file list runs everything"     --install "" true

    [ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
    echo "all ok"
    touch $out
  ''
