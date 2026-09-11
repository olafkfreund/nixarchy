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
    # README does not run the VM, and the pair below is the claim: exempt
    # from the INSTALL question, still relevant to the BUILD one. The guard
    # that matters -- build.yml deriving the app and command counts from
    # data/ and grepping README for them, which caught #424 -- lives in the
    # omarchy job, which the install gate never covered.
    t "README does not run the VM"             --install "README.md" false

    # `AGENTS.md` matched at the ROOT only, so installer/AGENTS.md ran a
    # 26-46 minute VM install for a markdown file. Every depth, because
    # `case` globs cross `/` and the fix relies on that.
    t "a nested AGENTS.md does not run the VM"  --install "installer/AGENTS.md" false
    t "nor a deeper one"                        --install "a/b/AGENTS.md" false
    t "nor the root one"                        --install "AGENTS.md" false

    echo "the build question, unchanged:"
    t "an unrelated check still builds"        "" "tests/substitutable.nix" true
    # The half of the README pair that keeps #424's guard honest. If this
    # ever flips to false, a README whose counts disagree with data/ merges
    # without the omarchy job ever looking at it.
    t "README still builds"                    "" "README.md" true
    t "the gate itself always does"            "" ".github/scripts/pr-touches-build.sh" true
    t "a nested AGENTS.md builds nothing"      "" "modules/AGENTS.md" false
    t "install-check.yml always does"          "" ".github/workflows/install-check.yml" true

    # This line used to read `t "docs still do not" "" "docs/…" false`, and it
    # was asserting the ARRANGEMENT rather than the property -- it made a real
    # hole look deliberate. Eight derivations take `docs/` or
    # `.github/scripts/` as INPUTS, so both provably CAN change a derivation,
    # which is the one thing the denylist promises its entries cannot do.
    #
    # A pull request editing only `omarchy-config-delta.sh` answered `false`,
    # so `checks.config-delta` -- the check whose entire job is testing that
    # script -- never ran on it. Same shape for package-delta, patched-files,
    # release-notes, bin-ledger, swap-guard and doc-options.
    #
    # `doc-options` reads `${../docs}` WHOLESALE, so this cannot be narrowed
    # to the doc files named in a grep: any page can move that output.
    echo "derivation inputs are not deniable (the build question):"
    t "a delta script builds"                  "" ".github/scripts/omarchy-config-delta.sh" true
    t "so does the package delta"              "" ".github/scripts/omarchy-package-delta.sh" true
    t "so does the patched-files script"       "" ".github/scripts/omarchy-patched-files.sh" true
    t "so do the release notes"                "" ".github/scripts/release-notes.sh" true
    t "so does the ledger checker"             "" ".github/scripts/check-bin-ledger.py" true
    t "a manual page builds (doc-options)"     "" "docs/manual/android.md" true
    t "so does the troubleshooting page"       "" "docs/manual/troubleshooting.md" true
    # A workflow file still cannot change a derivation, so the rest of
    # `.github/` stays denied -- narrowing this arm must not widen that one.
    t "an unrelated workflow still does not"   "" ".github/workflows/release.yml" false

    echo "and none of them runs the install VM:"
    # The expensive saving is the one that must survive this change: the three
    # checks the install job builds import only ./hardware-configuration.nix
    # and ./test-instrumentation.nix, so none of these can reach an install.
    t "a delta script does not"                --install ".github/scripts/omarchy-config-delta.sh" false
    t "the troubleshooting page does not"      --install "docs/manual/troubleshooting.md" false

    echo "fails safe:"
    # An empty list means the question could not be answered -- a paginated API
    # call that returned nothing, a renamed field. Unknown must mean run
    # everything, because the cheap answer skips every build.
    t "an empty file list runs everything"     --install "" true

    [ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
    echo "all ok"
    touch $out
  ''
