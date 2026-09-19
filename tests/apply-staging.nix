{ inputs, pkgs }:
# #720: nixarchy-apply writes the app selection into hosts/<hostname>/ when that
# directory exists, and staged paths relative to the flake ROOT. On a per-host
# layout the copies were never staged -- and a flake in a git repository sees
# only tracked or staged files, so the next rebuild dies on "path does not
# exist", with the staging failure hidden behind a note (CLAUDE.md §5).
#
# The layout is the variable that separates the two cases (§3), so both are run
# here: a root-only flake and a hosts/<hostname> one. Reported by a user against
# v4.0.3-1, who had patched it locally.
#
# A runCommand and not a VM: the whole bug is which directory git runs in.
# checks.session boots a desktop for minutes and has one flake layout, so it
# could not see the per-host case at all. The script comes out of the built
# system profile rather than being copied here, so it cannot drift from what the
# module actually ships.
let
  # The script alone, not the system profile it ships in. Taking it from
  # `system.build.toplevel` pulled a whole desktop closure into build.yml's
  # hosted `omarchy` job, whose runner has ~14 GB of disk: the job went quiet
  # and the runner was killed with SIGTERM, which reads as nothing at all.
  # Evaluating the module is unavoidable (the script is built by
  # writeShellApplication inside it); BUILDING the system is not.
  apply = builtins.head (
    builtins.filter (
      p: (p.pname or p.name or "") == "nixarchy-apply"
    ) inputs.self.nixosConfigurations.vm.config.environment.systemPackages
  );
in
pkgs.runCommand "nixarchy-apply-staging"
  {
    nativeBuildInputs = [
      pkgs.git
      pkgs.nix
    ];
  }
  ''
    export HOME=$PWD/home
    mkdir -p "$HOME"
    apply=${apply}/bin/nixarchy-apply
    [ -x "$apply" ] || { echo "nixarchy-apply is not where the module builds it" >&2; exit 1; }

    host=$(uname -n)
    fails=0
    ok() { echo "  ok      $1"; }
    bad() { echo "  FAILED  $1"; fails=$((fails + 1)); }

    # The selection nixarchy-apply reads.
    mkdir -p "$HOME/.config/nixarchy"
    cat > "$HOME/.config/nixarchy/apps.nix" <<'EOF'
    { programs.nixarchy.apps.ghostty.enable = true; }
    EOF

    # A fake nh: apply ends by rebuilding, which this check has no business
    # doing. It records each call and exits $NH_STUB_RC, so the flag cases
    # below can tell "switched" from "declined" and fake a failed rebuild.
    mkdir -p "$PWD/stub"
    printf '#!${pkgs.runtimeShell}\necho "$*" >> %s/nh.calls\nexit "''${NH_STUB_RC:-0}"\n' "$PWD" > "$PWD/stub/nh"
    chmod +x "$PWD/stub/nh"
    export PATH=$PWD/stub:$PATH

    # A flake with one tracked file of the user's own, so "did apply stage
    # anything it should not have" is answerable.
    newflake() { # newflake <dir> [hostdir]
      rm -rf "$1"; mkdir -p "$1"
      git -C "$1" init -q -b main
      git -C "$1" config user.email t@t; git -C "$1" config user.name t
      echo '{ }' > "$1/flake.nix"
      echo 'mine' > "$1/theirs.txt"
      git -C "$1" add -A; git -C "$1" -c commit.gpgsign=false commit -qm base
      [ -n "''${2:-}" ] && mkdir -p "$1/$2"
      # An unrelated edit, in the working tree and not staged. Apply must leave
      # it exactly like that.
      echo 'edited' > "$1/theirs.txt"
    }

    staged() { # staged <dir> <path> -> is it in the index?
      git -C "$1" status --porcelain -- "$2" | grep -qE '^[AM]'
    }

    # ---- per-host layout: the reported bug -------------------------------
    newflake "$PWD/per-host" "hosts/$host"
    NIXARCHY_FLAKE=$PWD/per-host $apply >/dev/null 2>&1 || true
    if [ -f "$PWD/per-host/hosts/$host/nixarchy-apps.nix" ]; then
      if staged "$PWD/per-host" "hosts/$host/nixarchy-apps.nix"; then
        ok "the per-host copy is staged"
      else
        bad "the per-host copy is NOT staged (#720): apply wrote hosts/$host/ and staged the flake root"
      fi
    else
      bad "apply did not write hosts/$host/nixarchy-apps.nix at all"
    fi

    # ---- root layout: today's behaviour, which must not regress ----------
    newflake "$PWD/root"
    NIXARCHY_FLAKE=$PWD/root $apply >/dev/null 2>&1 || true
    if staged "$PWD/root" nixarchy-apps.nix; then
      ok "the root copy is staged"
    else
      bad "the root copy is not staged"
    fi

    # ---- and nothing of the user's ---------------------------------------
    if git -C "$PWD/per-host" status --porcelain -- theirs.txt | grep -qE '^ M'; then
      ok "an unrelated edit is left unstaged"
    else
      bad "apply staged an unrelated edit: $(git -C "$PWD/per-host" status --porcelain -- theirs.txt)"
    fi

    # ---- twice is the same as once ---------------------------------------
    NIXARCHY_FLAKE=$PWD/per-host $apply >/dev/null 2>&1 || true
    if staged "$PWD/per-host" "hosts/$host/nixarchy-apps.nix"; then
      ok "a second apply leaves it staged"
    else
      bad "a second apply unstaged the copy"
    fi

    # ---- answers as flags (#765 PR 2) -----------------------------------
    # A panel or script has no terminal; it must be able to say "switch" and
    # "no preview" without feeding answers on stdin, and EOF must still decline.
    calls() { [ -s "$PWD/nh.calls" ]; }

    rm -f "$PWD/nh.calls"; rc=0
    NIXARCHY_FLAKE=$PWD/root $apply --yes --no-preview </dev/null >/dev/null 2>&1 || rc=$?
    if calls && [ "$rc" -eq 0 ]; then
      ok "--yes --no-preview switches with no stdin"
    else
      bad "--yes --no-preview did not switch (exit $rc, nh calls: $(cat "$PWD/nh.calls" 2>/dev/null))"
    fi

    rm -f "$PWD/nh.calls"; rc=0
    NIXARCHY_FLAKE=$PWD/root $apply </dev/null >/dev/null 2>&1 || rc=$?
    if calls; then
      bad "EOF on stdin switched; it must decline"
    else
      ok "EOF on stdin still declines"
    fi

    rm -f "$PWD/nh.calls"; rc=0
    NIXARCHY_FLAKE=$PWD/root $apply --frobnicate </dev/null >/dev/null 2>&1 || rc=$?
    if [ "$rc" -eq 2 ] && ! calls; then
      ok "an unknown flag exits 2 and never switches"
    else
      bad "an unknown flag exited $rc (want 2), nh calls: $(cat "$PWD/nh.calls" 2>/dev/null)"
    fi

    [ "$fails" -eq 0 ] || exit 1
    touch $out
  ''
