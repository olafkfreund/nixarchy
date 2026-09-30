{ pkgs, script }:
pkgs.runCommand "nixarchy-config-repo-ownership"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.git
      pkgs.gnugrep
      pkgs.gnused
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
      '[[ $1 == confirm ]]' > "$bin/gum"
    printf '%s\n' '#!${pkgs.bash}/bin/bash' \
      '[[ $1 == mark ]]' > "$bin/omarchy-done"
    printf '%s\n' '#!${pkgs.bash}/bin/bash' \
      'printf "%s\n" "$*" >> "$SUDO_LOG"' \
      '[[ $SUDO_MODE == allow ]] || exit 99' \
      'chmod u+w "$NIXARCHY_FLAKE"' \
      '"$@"; status=$?' \
      'chmod a-w "$NIXARCHY_FLAKE"' \
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
    run_case || fail "writable GitHub fixture failed: $(cat "$root/output")"
    test ! -s "$SUDO_LOG" || fail "sudo used for writable flake: $(cat "$SUDO_LOG")"
    test -f "$NIXARCHY_FLAKE/.gitignore" || fail "GitHub .gitignore missing"
    test -f "$NIXARCHY_FLAKE/.github/workflows/check.yml" || fail "GitHub CI file missing"
    test "$(stat -c %u "$NIXARCHY_FLAKE/.gitignore")" = "$(id -u)" || fail "GitHub .gitignore has wrong owner"
    test "$(stat -c %u "$NIXARCHY_FLAKE/.github/workflows")" = "$(id -u)" || fail "GitHub CI parent has wrong owner"
    test "$(stat -c %u "$NIXARCHY_FLAKE/.github/workflows/check.yml")" = "$(id -u)" || fail "GitHub CI file has wrong owner"
    grep -qF 'nix flake check --all-systems --no-build' "$NIXARCHY_FLAKE/.github/workflows/check.yml" || fail "GitHub CI content changed"
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
    chmod a-w "$NIXARCHY_FLAKE"
    run_case || fail "unwritable legacy fixture failed: $(cat "$root/output")"
    test -s "$SUDO_LOG" || fail "legacy flake did not request sudo"
    test -f "$NIXARCHY_FLAKE/.gitignore" || fail "legacy .gitignore missing"
    test -f "$NIXARCHY_FLAKE/.gitlab-ci.yml" || fail "legacy CI file missing"
    echo "config repo elevates only for an unwritable legacy flake"

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
