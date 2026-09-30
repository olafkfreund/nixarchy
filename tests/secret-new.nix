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
      pkgs.openssh
      pkgs.ssh-to-age
    ];
    inherit secret policyAdd;
  }
  ''
    set -o pipefail
    export HOME="$TMPDIR/home" XDG_DATA_HOME="$TMPDIR/data"
    mkdir -p "$HOME" "$XDG_DATA_HOME" "$TMPDIR/flat"
    ssh-keygen -q -t ed25519 -N "" -f "$TMPDIR/host_key"
    cp "$secret/bin/nixarchy-secret" "$TMPDIR/cli"
    sed -i "s|HOST_KEY=/etc/ssh/ssh_host_ed25519_key|HOST_KEY=$TMPDIR/host_key|" "$TMPDIR/cli"
    cli="$TMPDIR/cli"
    add="$policyAdd/bin/nixarchy-sops-policy-add"
    mkdir -p "$TMPDIR/stub"
    printf '%s\n' '#!/bin/sh' \
      '[ "$1" = mkdir ] || exit 1' \
      'shift' 'exec mkdir "$@"' > "$TMPDIR/stub/sudo"
    chmod +x "$TMPDIR/stub/sudo"
    export PATH="$TMPDIR/stub:$PATH"

    echo '== flat layout: refuse before any write'
    rc=0
    NIXARCHY_FLAKE="$TMPDIR/flat" "$cli" new demo > flat-output 2>&1 || rc=$?
    [ "$rc" -ne 0 ] || { echo 'FAIL: new accepted a flat flake'; exit 1; }
    [ ! -e "$TMPDIR/flat/hosts" ] && [ ! -e "$TMPDIR/flat/.sops.yaml" ] || {
      echo 'FAIL: new modified a flat flake'; exit 1; }
    grep -q 'Migrate a flat flake' flat-output || { echo 'FAIL: migration guidance missing'; exit 1; }
    echo '  ok: no host directory or policy created'

    echo '== user secrets remain independent of the flat guard'
    printf '%s\n' '#!/bin/sh' 'printf "%s\\n" "demo: value" > "$1"' > user-editor
    chmod +x user-editor
    mkdir -p "$XDG_DATA_HOME/nixarchy/secrets"
    cd "$XDG_DATA_HOME/nixarchy/secrets"
    NIXARCHY_FLAKE="$TMPDIR/flat" SOPS_EDITOR="$TMPDIR/user-editor" "$cli" new --user demo > user-output 2>&1 || {
      echo 'FAIL: user secret creation was blocked'; cat user-output; exit 1; }
    cd "$TMPDIR"
    decrypted=$(SOPS_AGE_KEY_FILE="$XDG_DATA_HOME/nixarchy/secrets/identity.txt" \
      sops -d "$XDG_DATA_HOME/nixarchy/secrets/user.yaml") || {
        echo 'FAIL: user secret did not decrypt'; exit 1; }
    grep -q '^demo: value$' <<< "$decrypted" || {
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
    cp "$host_sops" "$TMPDIR/host-wrapper"
    sed -i "s|key=/etc/ssh/ssh_host_ed25519_key|key=$TMPDIR/host_key|" "$TMPDIR/host-wrapper"
    grep -Fq "key=$TMPDIR/host_key" "$TMPDIR/host-wrapper" || {
      echo 'FAIL: fixture did not replace the root key path'; exit 1; }
    printf '%s\n' '#!/bin/sh' \
      '[ "$1" = --flag ] || exit 2' \
      '[ -z "''${SOPS_AGE_KEY+x}" ] || { echo "FAIL: editor inherited host key" >&2; exit 3; }' \
      'if grep -q "^edited:" "$2"; then' \
      '  sed -i "s/^edited:.*/edited: $CASE/" "$2"' \
      'else' \
      '  printf "edited: %s\\n" "$CASE" >> "$2"' \
      'fi' > editor
    chmod +x editor
    printf '%s\n' '#!/bin/sh' 'exit 9' > wrong-editor
    chmod +x wrong-editor
    printf '%s\n' '#!/bin/sh' 'exec "$TMPDIR/editor" --flag "$1"' > "$TMPDIR/stub/vi"
    chmod +x "$TMPDIR/stub/vi"
    mkdir -p hosts/alpha
    policy "$(ssh-to-age -i "$TMPDIR/host_key.pub")"
    printf '%s\n' 'entry: old' > hosts/alpha/secrets.yaml
    sops -e -i hosts/alpha/secrets.yaml
    key=$(ssh-to-age -private-key -i "$TMPDIR/host_key")
    check_edit() {
      decrypted=$(SOPS_AGE_KEY="$key" sops -d hosts/alpha/secrets.yaml) || {
        echo "FAIL: built wrapper could not decrypt editor case $1"; exit 1; }
      grep -q "^edited: $1$" <<< "$decrypted" || {
        echo "FAIL: built wrapper did not save editor case $1"; exit 1; }
    }
    env -u EDITOR CASE=1 SOPS_EDITOR="$TMPDIR/editor --flag" \
      timeout 20s "$TMPDIR/host-wrapper" edit hosts/alpha/secrets.yaml
    check_edit 1
    env -u SOPS_EDITOR CASE=2 EDITOR="$TMPDIR/editor --flag" \
      timeout 20s "$TMPDIR/host-wrapper" edit hosts/alpha/secrets.yaml
    check_edit 2
    CASE=3 SOPS_EDITOR="$TMPDIR/editor --flag" EDITOR="$TMPDIR/wrong-editor" \
      timeout 20s "$TMPDIR/host-wrapper" edit hosts/alpha/secrets.yaml
    check_edit 3
    env -u SOPS_EDITOR -u EDITOR CASE=4 \
      timeout 20s "$TMPDIR/host-wrapper" edit hosts/alpha/secrets.yaml
    check_edit 4
    echo '  ok: SOPS_EDITOR, EDITOR, precedence, and vi fallback; no editor received the key'

    touch "$out"
  ''
