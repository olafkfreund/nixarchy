{ pkgs, script }:
pkgs.runCommand "nixarchy-config-repo-ownership"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.age
      pkgs.coreutils
      pkgs.gawk
      pkgs.git
      pkgs.gnugrep
      pkgs.gnused
      pkgs.sops
    ];
  }
  ''
    fail() { echo "FAIL: $1" >&2; exit 1; }
    bin=$TMPDIR/bin
    mkdir -p "$bin"
    sed "s|MANAGED_MARKER=/etc/nixarchy/managed|MANAGED_MARKER=$TMPDIR/managed|" ${script} > "$TMPDIR/config-repo"
    chmod +x "$TMPDIR/config-repo"
    touch "$TMPDIR/managed"
    printf '%s\n' '#!${pkgs.bash}/bin/bash' \
      '[[ $1 == confirm && $* != *anyway* ]]' > "$bin/gum"
    printf '%s\n' '#!${pkgs.bash}/bin/bash' \
      '[[ $1 == mark ]]' > "$bin/omarchy-done"
    printf '%s\n' '#!${pkgs.bash}/bin/bash' \
      'printf "%s\n" "$*" >> "$SUDO_LOG"' \
      '[[ $SUDO_MODE == allow ]] || exit 99' \
      'chmod u+w "$NIXARCHY_FLAKE" "$NIXARCHY_FLAKE/.git"' \
      '"$@"; status=$?' \
      'chmod a-w "$NIXARCHY_FLAKE" "$NIXARCHY_FLAKE/.git"' \
      'exit "$status"' > "$bin/sudo"
    chmod +x "$bin"/*
    export PATH="$bin:$PATH"

    setup() {
      case_name=$1
      provider=$2
      root=$TMPDIR/$case_name
      export HOME=$root/home NIXARCHY_FLAKE=$root/flake SUDO_LOG=$root/sudo.log
      mkdir -p "$HOME" "$NIXARCHY_FLAKE" "$root/$provider"
      : > "$SUDO_LOG"
      git config --global user.name Test
      git config --global user.email test@example.invalid
      git init -q "$NIXARCHY_FLAKE"
      git init --bare -q "$root/$provider/repo.git"
      git -C "$NIXARCHY_FLAKE" remote add origin "$root/$provider/repo.git"
    }
    run_case() {
      bash "$TMPDIR/config-repo" --force > "$root/output" 2>&1
    }

    setup github github.com
    export SUDO_MODE=deny
    if ! run_case; then
      test ! -s "$SUDO_LOG" || fail "sudo used for writable flake: $(cat "$SUDO_LOG")"
      fail "writable GitHub fixture failed: $(cat "$root/output")"
    fi
    test ! -s "$SUDO_LOG" || fail "sudo used for writable flake: $(cat "$SUDO_LOG")"
    test -f "$NIXARCHY_FLAKE/.gitignore" || fail "GitHub .gitignore missing"
    test -f "$NIXARCHY_FLAKE/.github/workflows/check.yml" || fail "GitHub CI file missing"
    test "$(stat -c %u "$NIXARCHY_FLAKE/.gitignore")" = "$(id -u)" || fail "GitHub .gitignore has wrong owner"
    test "$(stat -c %u "$NIXARCHY_FLAKE/.github/workflows")" = "$(id -u)" || fail "GitHub CI parent has wrong owner"
    test "$(stat -c %u "$NIXARCHY_FLAKE/.github/workflows/check.yml")" = "$(id -u)" || fail "GitHub CI file has wrong owner"
    grep -qF 'nix flake check --all-systems --no-build' "$NIXARCHY_FLAKE/.github/workflows/check.yml" || fail "GitHub CI content changed"
    sed -E 's/\x1B\[[0-9;]*[[:alpha:]]//g' "$root/output" > "$root/plain"
    grep -Fxq "    git add -A && git commit -m 'what changed'" "$root/plain" || fail "writable hint did not show plain git add/commit"
    grep -Fxq '    git push' "$root/plain" || fail "writable hint did not show plain git push"
    if grep -Fq 'sudo git' "$root/plain"; then fail "writable hint suggested sudo git"; fi
    echo "config repo suggests plain git for writable metadata"
    echo "config repo writes GitHub files without sudo"

    setup gitlab gitlab.com
    export SUDO_MODE=deny
    run_case || fail "writable GitLab fixture failed: $(cat "$root/output")"
    test ! -s "$SUDO_LOG" || fail "sudo used for writable GitLab flake"
    test -f "$NIXARCHY_FLAKE/.gitlab-ci.yml" || fail "GitLab CI file missing"
    test "$(stat -c %u "$NIXARCHY_FLAKE/.gitlab-ci.yml")" = "$(id -u)" || fail "GitLab CI file has wrong owner"
    grep -qF 'nix flake check --all-systems --no-build' "$NIXARCHY_FLAKE/.gitlab-ci.yml" || fail "GitLab CI content changed"
    echo "config repo writes GitLab files without sudo"

    setup existing github.com
    export SUDO_MODE=deny
    printf 'keep this file\n' > "$NIXARCHY_FLAKE/.gitignore"
    cp "$NIXARCHY_FLAKE/.gitignore" "$root/original"
    run_case || fail "pre-existing file fixture failed: $(cat "$root/output")"
    cmp -s "$root/original" "$NIXARCHY_FLAKE/.gitignore" || fail "pre-existing .gitignore changed"
    test ! -s "$SUDO_LOG" || fail "sudo used for pre-existing file"
    echo "config repo leaves existing files unchanged"

    setup legacy gitlab.com
    export SUDO_MODE=allow
    chmod a-w "$NIXARCHY_FLAKE" "$NIXARCHY_FLAKE/.git"
    run_case || fail "unwritable legacy fixture failed: $(cat "$root/output")"
    test -s "$SUDO_LOG" || fail "legacy flake did not request sudo"
    test -f "$NIXARCHY_FLAKE/.gitignore" || fail "legacy .gitignore missing"
    test -f "$NIXARCHY_FLAKE/.gitlab-ci.yml" || fail "legacy CI file missing"
    sed -E 's/\x1B\[[0-9;]*[[:alpha:]]//g' "$root/output" > "$root/plain"
    grep -Fxq "    sudo git add -A && sudo git commit -m 'what changed'" "$root/plain" || fail "legacy hint did not show sudo git add/commit"
    grep -Fxq '    sudo git push' "$root/plain" || fail "legacy hint did not show sudo git push"
    echo "config repo suggests sudo git for legacy metadata"
    echo "config repo elevates only for an unwritable legacy flake"

    # A real sops file, so the fixture is sops' own output rather than a guess.
    mkdir -p "$TMPDIR/fix/hosts/alpha"
    (
      cd "$TMPDIR/fix"
      age-keygen -o alpha.key 2>/dev/null
      printf '%s\n' \
        'creation_rules:' \
        '  - path_regex: hosts/alpha/secrets\.yaml$' \
        '    age: '"$(age-keygen -y alpha.key)" > .sops.yaml
      printf '%s\n' 'hypr-rdp-password: s3cret-value' > hosts/alpha/secrets.yaml
      SOPS_AGE_KEY_FILE=alpha.key sops -e -i hosts/alpha/secrets.yaml
    ) || fail "could not generate the sops fixture"
    grep -q 'ENC\[AES256_GCM' "$TMPDIR/fix/hosts/alpha/secrets.yaml" || fail "sops fixture is not encrypted"

    setup secrets-encrypted github.com
    export SUDO_MODE=deny
    mkdir -p "$NIXARCHY_FLAKE/hosts/alpha"
    cp "$TMPDIR/fix/hosts/alpha/secrets.yaml" "$NIXARCHY_FLAKE/hosts/alpha/secrets.yaml"
    run_case || fail "encrypted secrets fixture failed: $(cat "$root/output")"
    git -C "$NIXARCHY_FLAKE" rev-parse HEAD >/dev/null 2>&1 || fail "encrypted secrets file was not committed: $(cat "$root/output")"
    if grep -q 'NOT encrypted' "$root/output"; then fail "sops-encrypted file was called plaintext"; fi

    setup secrets-mixed github.com
    export SUDO_MODE=deny
    mkdir -p "$NIXARCHY_FLAKE/hosts/alpha"
    cp "$TMPDIR/fix/hosts/alpha/secrets.yaml" "$NIXARCHY_FLAKE/hosts/alpha/secrets.yaml"
    chmod u+w "$NIXARCHY_FLAKE/hosts/alpha/secrets.yaml"
    printf 'extra-token: plain-value-123\n' >> "$NIXARCHY_FLAKE/hosts/alpha/secrets.yaml"
    run_case || true
    grep -q 'NOT encrypted' "$root/output" || fail "partly plaintext secrets file was not flagged: $(cat "$root/output")"
    grep -q 'extra-token' "$root/output" || fail "plaintext key was not named: $(cat "$root/output")"
    if grep -q 'plain-value-123' "$root/output"; then fail "the plaintext value was printed"; fi
    if git -C "$NIXARCHY_FLAKE" rev-parse HEAD >/dev/null 2>&1; then fail "partly plaintext secrets file was committed"; fi

    setup secrets-plain github.com
    export SUDO_MODE=deny
    mkdir -p "$NIXARCHY_FLAKE/hosts/alpha"
    printf 'hypr-rdp-password: s3cret-value\n' > "$NIXARCHY_FLAKE/hosts/alpha/secrets.yaml"
    run_case || true
    grep -q 'NOT encrypted' "$root/output" || fail "plaintext secrets file was not flagged: $(cat "$root/output")"
    if git -C "$NIXARCHY_FLAKE" rev-parse HEAD >/dev/null 2>&1; then fail "plaintext secrets file was committed"; fi
    echo "config repo checks every secrets value, not the file"

    setup mixed github.com
    export SUDO_MODE=deny
    mkdir -p "$NIXARCHY_FLAKE/.github"
    chmod a-w "$NIXARCHY_FLAKE/.github"
    if run_case; then fail "mixed-ownership flake unexpectedly succeeded"; fi
    grep -qF 'fix its parent directory ownership' "$root/output" || fail "mixed-ownership refusal lacked diagnosis: $(cat "$root/output")"
    test ! -s "$SUDO_LOG" || fail "mixed-ownership flake used sudo"
    test ! -e "$NIXARCHY_FLAKE/.github/workflows" || fail "mixed-ownership flake changed CI parent"
    echo "config repo refuses an unwritable parent in a writable flake"

    mkdir -p "$out"
  ''
