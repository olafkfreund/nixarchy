{
  pkgs,
  secret,
  policyAdd,
}:
pkgs.runCommand "nixarchy-secret-new"
  {
    nativeBuildInputs = [
      pkgs.age
      pkgs.sops
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
    inherit secret policyAdd;
  }
  ''
    set -o pipefail
    export HOME="$TMPDIR/home" XDG_DATA_HOME="$TMPDIR/data"
    mkdir -p "$HOME" "$XDG_DATA_HOME" "$TMPDIR/flat"
    cli="$secret/bin/nixarchy-secret"
    add="$policyAdd/bin/nixarchy-sops-policy-add"

    echo '== flat layout: refuse before any write'
    rc=0
    NIXARCHY_FLAKE="$TMPDIR/flat" "$cli" new demo > flat-output 2>&1 || rc=$?
    [ "$rc" -ne 0 ] || { echo 'FAIL: new accepted a flat flake'; exit 1; }
    grep -q 'Migrate the flake' flat-output || { echo 'FAIL: migration guidance missing'; exit 1; }
    [ ! -e "$TMPDIR/flat/hosts" ] && [ ! -e "$TMPDIR/flat/.sops.yaml" ] || {
      echo 'FAIL: new modified a flat flake'; exit 1; }
    echo '  ok: no host directory or policy created'

    echo '== user secrets remain independent of the flat guard'
    printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "demo: value" > "$1"' > user-editor
    chmod +x user-editor
    NIXARCHY_FLAKE="$TMPDIR/flat" SOPS_EDITOR="$TMPDIR/user-editor" "$cli" new --user demo > user-output 2>&1 || {
      echo 'FAIL: user secret creation was blocked'; cat user-output; exit 1; }
    SOPS_AGE_KEY_FILE="$XDG_DATA_HOME/nixarchy/secrets/identity.txt" \
      sops -d "$XDG_DATA_HOME/nixarchy/secrets/user.yaml" | grep -q '^demo: value$' || {
        echo 'FAIL: user secret did not decrypt'; exit 1; }
    echo '  ok: user secret encrypted and read back'

    echo '== exact policy recipient checks'
    age-keygen -o alpha.key 2>/dev/null
    age-keygen -o beta.key 2>/dev/null
    A=$(age-keygen -y alpha.key)
    B=$(age-keygen -y beta.key)
    policy() {
      printf '%s\n' \
        'keys:' "  - &alpha $1" \
        'creation_rules:' \
        '  - path_regex: hosts/alpha/secrets\.yaml$' \
        '    key_groups:' '      - age:' '          - *alpha' \
        > .sops.yaml
    }
    expect_rc() {
      want=$1; shift
      rc=0
      "$@" > reply 2>&1 || rc=$?
      [ "$rc" -eq "$want" ] || {
        echo "FAIL: wanted exit $want, got $rc"; cat reply; exit 1; }
    }
    policy "$A"
    before=$(sha256sum .sops.yaml)
    expect_rc 2 "$add" --check .sops.yaml alpha "$A"
    expect_rc 3 "$add" --check .sops.yaml alpha "$B"
    [ "$(sha256sum .sops.yaml)" = "$before" ] || {
      echo 'FAIL: read-only check changed policy'; exit 1; }
    policy "$B"
    expect_rc 3 "$add" --check .sops.yaml alpha "$A"
    printf '%s\n' '  - path_regex: hosts/alpha/secrets\.yaml$' \
      '    key_groups:' '      - age:' "          - $A" >> .sops.yaml
    expect_rc 3 "$add" --check .sops.yaml alpha "$A"
    printf '%s\n' '# hosts/alpha/secrets.yaml' 'creation_rules: []' > .sops.yaml
    expect_rc 4 "$add" --check .sops.yaml alpha "$A"
    printf '%s\n' 'creation_rules:' \
      '  - path_regex: hosts/beta/secrets\.yaml$' \
      '    key_groups:' '      - age:' "          - $A" > .sops.yaml
    expect_rc 4 "$add" --check .sops.yaml alpha "$A"
    grep -Fq '"$POLICY_ADD" --check' "$cli" || {
      echo 'FAIL: new does not use the read-only policy check'; exit 1; }
    echo '  ok: matching, stale, duplicate, comment, and other-host rules'

    echo '== SOPS editor receives no host key'
    host_sops=$(sed -n 's/^HOST_SOPS=//p' "$cli")
    [ -n "$host_sops" ] && [ -f "$host_sops" ] || {
      echo 'FAIL: built CLI has no root-side SOPS wrapper'; exit 1; }
    grep -Fq 'SOPS_EDITOR="env -u SOPS_AGE_KEY $editor"' "$host_sops" || {
      echo 'FAIL: root-side SOPS wrapper does not scrub the editor'; exit 1; }
    grep -Fq 'SOPS_EDITOR:-' "$host_sops" && grep -Fq 'EDITOR:-' "$host_sops" || {
      echo 'FAIL: SOPS_EDITOR/EDITOR preference is missing'; exit 1; }
    printf '%s\n' '#!/bin/sh' \
      '[ "$1" = --flag ] || exit 2' \
      '[ -z "''${SOPS_AGE_KEY+x}" ] || { echo "FAIL: editor inherited host key" >&2; exit 3; }' \
      'printf "%s\\n" "edited: yes" >> "$2"' > editor
    chmod +x editor
    mkdir -p hosts/alpha
    policy "$A"
    printf '%s\n' 'entry: old' > hosts/alpha/secrets.yaml
    SOPS_AGE_KEY_FILE=alpha.key sops -e -i hosts/alpha/secrets.yaml
    key=$(grep '^AGE-SECRET-KEY-' alpha.key)
    SOPS_AGE_KEY="$key" SOPS_EDITOR="env -u SOPS_AGE_KEY $TMPDIR/editor --flag" \
      sops edit hosts/alpha/secrets.yaml
    SOPS_AGE_KEY_FILE=alpha.key sops -d hosts/alpha/secrets.yaml | grep -q '^edited: yes$' || {
      echo 'FAIL: SOPS could not decrypt and save through SOPS_EDITOR'; exit 1; }
    SOPS_AGE_KEY="$key" EDITOR="$TMPDIR/editor --flag" \
      SOPS_EDITOR="env -u SOPS_AGE_KEY $TMPDIR/editor --flag" \
      sops edit hosts/alpha/secrets.yaml
    SOPS_AGE_KEY_FILE=alpha.key sops -d hosts/alpha/secrets.yaml | grep -q '^edited: yes$' || {
      echo 'FAIL: SOPS could not decrypt and save through EDITOR'; exit 1; }
    echo '  ok: SOPS saved, editor received no key'

    touch "$out"
  ''
