{ pkgs, ... }:
# #1711: a failed nightly's issue says why, without its run. nightly-digest.sh
# reads the run's jobs from the API, finds each failed job's build targets in
# nightly.yml, and prints the failing derivation's log excerpt. `gh`, `nix` and
# `nix-store` are stubs (tests/nightly-digest/bin) that serve one directory per
# case (tests/nightly-digest/cases) over a shared universe of derivations
# (tests/nightly-digest/common); nightly.yml is the real file, so a renamed job
# or target shows up here.
pkgs.runCommand "nixarchy-nightly-digest"
  {
    nativeBuildInputs = with pkgs; [
      bash
      gnused
      gawk
      gnugrep
      coreutils
      jq
      yq-go
    ];
  }
  ''
    root=$PWD
    mkdir -p work/.github/workflows work/.github/scripts
    cp ${../.github/workflows/nightly.yml} work/.github/workflows/nightly.yml
    cp ${../.github/scripts/nightly-digest.sh} work/.github/scripts/nightly-digest.sh
    cp ${../.github/scripts/failure-excerpt.sh} work/.github/scripts/failure-excerpt.sh
    cp -r ${./nightly-digest/bin} bin
    chmod -R u+wx bin work/.github/scripts
    patchShebangs bin work/.github/scripts
    export PATH="$root/bin:$PATH"

    fail() { echo "FAIL: $*" >&2; exit 1; }
    # run <case> [VAR=value ...]: the digest text lands in text-<case>.txt,
    # parsed from the GITHUB_OUTPUT file the case set, never from stdout.
    run() {
      c=$1; shift
      : > "$root/out-$c.txt"
      (cd work && env STUB_CASE=${./nightly-digest}/cases/$c STUB_COMMON=${./nightly-digest}/common \
        GITHUB_OUTPUT="$root/out-$c.txt" GH_REPO=o/r RUN_ID=1 "$@" \
        bash .github/scripts/nightly-digest.sh > "$root/stdout-$c.txt") \
        || fail "$c: the digest exited non-zero"
      awk '/^text<</ { d = substr($0, 7); inb = 1; next }
        inb && $0 == d { closed = 1; exit }
        inb { print }
        END { exit !(inb && closed) }' "$root/out-$c.txt" > "text-$c.txt" \
        || fail "$c: no closed text<<DELIM block in GITHUB_OUTPUT"
    }
    has() {
      if ! grep -qF -- "$2" "text-$1.txt"; then cat "text-$1.txt" >&2; fail "$1: digest lacks: $2"; fi
    }
    lacks() {
      if grep -qF -- "$2" "text-$1.txt"; then cat "text-$1.txt" >&2; fail "$1: digest has: $2"; fi
    }
    hasline() {
      if ! grep -qxF -- "$2" "text-$1.txt"; then cat "text-$1.txt" >&2; fail "$1: digest lacks the line: $2"; fi
    }

    run c1-traceback
    has c1-traceback '### install onto a blank disk: failed at step "Install onto a blank disk and boot the result"'
    has c1-traceback '**vm-test-run-nixarchy-install**'
    has c1-traceback 'Traceback (most recent call last):'
    has c1-traceback 'RuntimeError: the installed system did not boot'
    hasline c1-traceback 'installer-vm: built'
    lacks c1-traceback 'report a failure'

    run c2-timeout
    has c2-timeout '### install from the network ISO: timed out at step "Install from the NETWORK ISO, fetching the closure"'
    has c2-timeout 'boot step 15 of install'
    has c2-timeout 'boot step 6 of install'
    lacks c2-timeout 'boot step 5 of install'

    run c3-iso-size
    has c3-iso-size '### install from the network ISO: failed at step "Report the ISO size"'
    hasline c3-iso-size 'iso-net: built'
    hasline c3-iso-size 'checks.x86_64-linux.iso-budget: no build log (it never started, or it was substituted)'
    hasline c3-iso-size 'checks.x86_64-linux.install-iso-net: no build log (it never started, or it was substituted)'
    lacks c3-iso-size '```'

    run c4-canary
    hasline c4-canary '### what a user'"'"'s flake update gets: failed at step "Their machine still evaluates"'
    [ "$(grep -c . text-c4-canary.txt)" = 1 ] || { cat text-c4-canary.txt >&2; fail "c4-canary: more than the header"; }

    run c5-empty-log
    has c5-empty-log '### type through LUKS, greeter and lock screen: failed at step "Type through LUKS"'
    hasline c5-empty-log 'checks.x86_64-linux.keyboard-boot: no build log (it never started, or it was substituted)'
    lacks c5-empty-log '```'

    run c6-gh-fails STUB_GH_FAIL=1
    has c6-gh-fails 'digest unavailable:'
    [ "$(sed -n 1p text-c6-gh-fails.txt | cut -c1-19)" = 'digest unavailable:' ] \
      || { cat text-c6-gh-fails.txt >&2; fail "c6-gh-fails: text must start with digest unavailable:"; }

    run c7-cap DIGEST_MAX=2000
    size=$(wc -c < text-c7-cap.txt)
    if [ "$size" -gt 2000 ]; then fail "c7-cap: $size characters, over DIGEST_MAX=2000"; fi
    [ "$(grep -c '^### ' text-c7-cap.txt)" = 4 ] || { cat text-c7-cap.txt >&2; fail "c7-cap: expected all four headers"; }
    has c7-cap '(excerpt truncated)'

    run c8-dependency
    has c8-dependency 'checks.x86_64-linux.install-iso-net:'
    has c8-dependency '**linux-7.2.11-modules**'
    has c8-dependency 'conflicting subpath in the module tree'
    hasline c8-dependency 'iso-net: built'

    run c9-cancelled
    has c9-cancelled '### type through LUKS, greeter and lock screen: cancelled: Canceling since a higher priority waiting request for nixarchy-install-vm-1 exists at step "Type through LUKS"'
    lacks c9-cancelled 'timed out'

    run c10-redaction
    has c10-redaction '[line removed: looked like a secret]'
    has c10-redaction 'error: the install check failed'
    lacks c10-redaction 'ghp_'
    lacks c10-redaction 's3cr3t'
    lacks c10-redaction 'CACHIX_AUTH_TOKEN'

    # Wiring: the real nightly.yml hands the digest to report, through env only.
    wf=work/.github/workflows/nightly.yml
    q() { yq "$1" "$wf"; }
    want() { # <what> <expected> <yq expression>
      got=$(q "$3") || fail "wiring: yq failed on $3"
      if [ "$got" != "$2" ]; then fail "wiring: $1: expected '$2', got '$got'"; fi
    }
    want "the digest step runs nightly-digest.sh" 1 \
      '[.jobs.digest.steps[] | select(.id == "digest") | select(.run | contains("nightly-digest.sh"))] | length'
    want "digest.outputs.text" '$'"{{ steps.digest.outputs.text }}" '.jobs.digest.outputs.text'
    want "the digest step has GH_TOKEN" 1 \
      '[.jobs.digest.steps[] | select(.id == "digest") | select(.env | has("GH_TOKEN"))] | length'
    want "digest.if equals report.if" "$(q '.jobs.report.if')" '.jobs.digest.if'
    if [ -z "$(q '.jobs.report.if')" ] || [ "$(q '.jobs.report.if')" = null ]; then fail "wiring: report has no if"; fi
    want "report.needs contains digest" 1 '[.jobs.report.needs[] | select(. == "digest")] | length'
    want "a report step env carries DIGEST" 1 \
      '[.jobs.report.steps[] | select(.env) | select(.env | has("DIGEST"))] | length'
    want "no run: contains needs.digest.outputs" 0 \
      '[.jobs[].steps[] | select(.run) | select(.run | contains("needs.digest.outputs"))] | length'

    echo "nightly-digest: ten cases name the job, step and failing log, and every run exits 0"
    touch $out
  ''
