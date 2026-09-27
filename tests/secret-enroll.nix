{ pkgs, policyAdd }:
# `nixarchy secret enroll` adds a second machine to a .sops.yaml that already
# describes a first one -- and the property that matters is not that the YAML
# gained a line. It is that the new host can encrypt a file only it can read,
# while the first host's rule, anchor and existing file are untouched.
#
# WHAT IS UNDER TEST, and why it is not the CLI. `nixarchy secret enroll`
# cannot be driven in a sandbox: it reads the hostname from
# /proc/sys/kernel/hostname and its recipient from
# /etc/ssh/ssh_host_ed25519_key.pub, and a build sandbox has no /etc/ssh and
# reports `localhost`. Measured, not assumed. So the decision and the write
# live in pkgs/sops-policy-add.nix and this runs THAT, which is the code the
# CLI runs -- the argument pkgs/ai-mirror-mcp-remove.nix already makes.
#
# THE SELF-TEST, per §1. Before enrolling, beta must be UNABLE to encrypt:
# sops answers `no matching creation rules found` for a path no rule covers.
# If that ever succeeds, this check cannot show that enroll did anything, and
# it fails immediately rather than reporting a green it has not earned.
#
# The fixture is written with printf rather than a heredoc on purpose: a
# heredoc body inside an indented Nix string has to start at column zero,
# which lowers the block's common indentation and makes nixfmt rewrite the
# whole file around it (#802).
pkgs.runCommand "nixarchy-secret-enroll"
  {
    nativeBuildInputs = [
      pkgs.age
      pkgs.sops
      pkgs.yq-go
    ];
    inherit policyAdd;
  }
  ''
    set -o pipefail
    export HOME=$TMPDIR
    cd "$TMPDIR"
    mkdir -p hosts/alpha hosts/beta

    add="$policyAdd/bin/nixarchy-sops-policy-add"

    age-keygen -o alpha.key 2>/dev/null
    age-keygen -o beta.key  2>/dev/null
    A=$(age-keygen -y alpha.key)
    B=$(age-keygen -y beta.key)

    # A hand-written first host, anchors and all -- the shape `nixarchy secret
    # new` writes. The anchor matters: it is the part of YAML that round-trips
    # worst, and this check exists partly to prove yq leaves it alone.
    printf '%s\n' \
      '# Which recipients can decrypt which file. Written by nixarchy secret.' \
      'keys:' \
      "  - &alpha $A" \
      'creation_rules:' \
      '  - path_regex: hosts/alpha/secrets\.yaml$' \
      '    key_groups:' \
      '      - age:' \
      '          - *alpha' \
      > .sops.yaml

    printf '%s\n' 'hypr-rdp-password: alpha-only' > hosts/alpha/secrets.yaml
    SOPS_AGE_KEY_FILE=alpha.key sops -e -i hosts/alpha/secrets.yaml

    echo "== self-test: with no rule, beta must NOT be able to encrypt"
    printf '%s\n' 'hypr-rdp-password: beta-only' > hosts/beta/secrets.yaml
    if SOPS_AGE_KEY_FILE=beta.key sops -e -i hosts/beta/secrets.yaml 2>/dev/null; then
      echo "FAIL: sops encrypted hosts/beta with no creation rule for it."
      echo "  This check cannot then show that enroll did anything."
      exit 1
    fi
    echo "  ok: refused, so the rule is what makes the difference"

    echo "== enroll beta"
    "$add" .sops.yaml beta "$B"

    echo "== beta encrypts and reads back its own file"
    SOPS_AGE_KEY_FILE=beta.key sops -e -i hosts/beta/secrets.yaml
    got=$(SOPS_AGE_KEY_FILE=beta.key sops -d hosts/beta/secrets.yaml)
    [ "$got" = "hypr-rdp-password: beta-only" ] || {
      echo "FAIL: beta could not read back its own secret; got: $got"; exit 1; }
    echo "  ok"

    echo "== alpha must NOT be able to read beta's file"
    if SOPS_AGE_KEY_FILE=alpha.key sops -d hosts/beta/secrets.yaml >/dev/null 2>&1; then
      echo "FAIL: alpha decrypted beta's secret. Per-host isolation is the"
      echo "  whole reason these are per-host rather than one shared file."
      exit 1
    fi
    echo "  ok: refused"

    echo "== alpha's own file still decrypts, and its rule is untouched"
    got=$(SOPS_AGE_KEY_FILE=alpha.key sops -d hosts/alpha/secrets.yaml)
    [ "$got" = "hypr-rdp-password: alpha-only" ] || {
      echo "FAIL: alpha's secret changed; got: $got"; exit 1; }
    grep -q '  - &alpha ' .sops.yaml || {
      echo "FAIL: alpha's YAML anchor was rewritten."; exit 1; }
    grep -q '          - \*alpha' .sops.yaml || {
      echo "FAIL: alpha's alias reference was rewritten."; exit 1; }
    grep -q '^# Which recipients' .sops.yaml || {
      echo "FAIL: the policy's leading comment was dropped."; exit 1; }
    echo "  ok: anchor, alias and comment all survived"

    echo "== a second run is a no-op, exit 2, and adds no rule"
    rc=0; "$add" .sops.yaml beta "$B" || rc=$?
    [ "$rc" = 2 ] || { echo "FAIL: expected exit 2, got $rc"; exit 1; }
    n=$(grep -c 'hosts/beta/secrets' .sops.yaml)
    [ "$n" = 1 ] || { echo "FAIL: expected 1 rule for beta, found $n"; exit 1; }
    echo "  ok"

    echo "== a CHANGED recipient is reported, exit 3, and nothing is appended"
    before=$(sha256sum .sops.yaml | cut -d' ' -f1)
    rc=0; "$add" .sops.yaml beta "$A" || rc=$?
    [ "$rc" = 3 ] || { echo "FAIL: expected exit 3, got $rc"; exit 1; }
    after=$(sha256sum .sops.yaml | cut -d' ' -f1)
    [ "$before" = "$after" ] || {
      echo "FAIL: the policy was modified on a recipient mismatch."
      echo "  Two rules for one path is worse than none: sops takes the first,"
      echo "  so the machine would encrypt to a key it cannot read back."
      exit 1; }
    echo "  ok: reported and left alone"

    echo "== a missing policy is an error, not a new file"
    rc=0; "$add" nowhere.yaml beta "$B" >/dev/null 2>&1 || rc=$?
    [ "$rc" = 1 ] || { echo "FAIL: expected exit 1, got $rc"; exit 1; }
    [ ! -e nowhere.yaml ] || { echo "FAIL: it created the policy."; exit 1; }
    echo "  ok"

    echo
    echo "enroll: per-host isolation holds, the first host is untouched,"
    echo "and both re-run cases refuse rather than duplicate."
    touch $out
  ''
