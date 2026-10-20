{ pkgs, ... }:
# #1384: a failed build job used to end in 25 lines of proofs and cascades,
# with neither the failing check's name nor its error. failure-digest.sh reads
# the captured build log and prints both. The fixtures are trimmed from real
# 2026-10-20 logs (tests/failure-digest/); `nix log` is a stub that serves each
# derivation's log from tests/failure-digest/nixlog/.
#
# Each fixture names what the old `tail -25` could not: a buried assertion, a
# failure followed by proofs, a root under cascades, and no failure at all.
# Every run must exit 0: the digest never changes a job's status.
pkgs.runCommand "nixarchy-failure-digest"
  {
    nativeBuildInputs = with pkgs; [
      bash
      gnused
      gawk
      gnugrep
      coreutils
    ];
  }
  ''
    mkdir -p sut bin
    cp ${../.github/scripts/failure-digest.sh} sut/failure-digest.sh
    cp ${../.github/scripts/failure-excerpt.sh} sut/failure-excerpt.sh
    printf '%s\n' '#!${pkgs.bash}/bin/bash' \
      '[ "$1" = log ] && cat "${./failure-digest}/nixlog/$(basename "$2")"' > bin/nix
    chmod +x bin/nix sut/*.sh
    patchShebangs sut
    export PATH="$PWD/bin:$PATH"

    fail() { echo "FAIL: $*" >&2; exit 1; }
    run() { # fixture -> digest-$1.txt, GITHUB_OUTPUT -> out-$1.txt
      : > out-$1.txt
      GITHUB_OUTPUT=$PWD/out-$1.txt bash sut/failure-digest.sh ${./failure-digest}/$1.log > digest-$1.txt \
        || fail "$1: the digest exited non-zero"
    }
    has() { grep -qF -- "$2" digest-$1.txt || { cat digest-$1.txt >&2; fail "$1: digest lacks: $2"; }; }
    lacks() { ! grep -qF -- "$2" digest-$1.txt || { cat digest-$1.txt >&2; fail "$1: digest has: $2"; }; }

    run a-session
    has a-session '✗ vm-test-run-nixarchy-session'
    has a-session 'RequestedAssertionFailed: action timed out'
    grep -qx 'digest=vm-test-run-nixarchy-session' out-a-session.txt || fail "a-session: GITHUB_OUTPUT"

    run b-proofs
    has b-proofs '✗ nixarchy-copilot-handoff'
    has b-proofs 'the failing-log excerpt has 0 lines'
    lacks b-proofs 'failed only because'

    run c-cascade
    has c-cascade '✗ linux-7.2.11-modules'
    has c-cascade 'conflicting subpath'
    has c-cascade '5 checks failed only because linux-7.2.11-modules failed'
    lacks c-cascade '✗ initrd'
    lacks c-cascade '✗ nixos-system'

    # A log captured twice (edge prepare's tee plus the script's) is one failure.
    cat ${./failure-digest}/c-cascade.log ${./failure-digest}/c-cascade.log > twice.log
    bash sut/failure-digest.sh $PWD/twice.log > digest-twice.txt || fail "twice: exited non-zero"
    [ "$(grep -c '✗ linux-7.2.11-modules' digest-twice.txt)" = 1 ] || { cat digest-twice.txt >&2; fail "twice: root listed more than once"; }
    has twice '5 checks failed only because linux-7.2.11-modules failed'

    run d-clean
    has d-clean 'no failed derivation found'
    grep -qx 'digest=' out-d-clean.txt || fail "d-clean: GITHUB_OUTPUT"

    # Never a status: a missing log, and a nix that dies, both still exit 0.
    bash sut/failure-digest.sh $PWD/does-not-exist.log >/dev/null || fail "missing log exited non-zero"
    printf '%s\n' '#!${pkgs.bash}/bin/bash' 'exit 3' > bin/nix
    bash sut/failure-digest.sh ${./failure-digest}/c-cascade.log >/dev/null || fail "dead nix log exited non-zero"

    echo "failure-digest: four fixtures name their check and its error; every run exits 0"
    touch $out
  ''
