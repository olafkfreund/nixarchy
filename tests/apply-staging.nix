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
  # The rebuild panel's state mapping (#765 PR 5), taken the same way. It is a
  # command precisely so it can be run here: nothing in the suite drives QML,
  # so a state machine left in the panel would ship untested.
  rebuildState = builtins.head (
    builtins.filter (
      p: (p.pname or p.name or "") == "nixarchy-rebuild-state"
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
    # doing. An exported FUNCTION, not a file on PATH: writeShellApplication
    # prepends its runtimeInputs, so the real nh would shadow any stub file.
    # Bash resolves functions before PATH. It records each call and returns
    # $NH_STUB_RC, so the cases below can tell "switched" from "declined".
    nhcalls=$PWD/nh.calls
    nh() { echo "$*" >> "$nhcalls"; return "''${NH_STUB_RC:-0}"; }
    export nhcalls
    export -f nh

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

    # ---- flatsnap rides along, and only when it exists (#904) ------------
    # The nixarchy.flatsnap plugin writes flatsnap.nix; nixarchy ships no
    # template for it. Both halves are asserted, because the "only when it
    # exists" half is what keeps a machine without the plugin untouched -- and
    # it is the half a loop that stopped skipping would break silently.
    newflake "$PWD/nofs"
    NIXARCHY_FLAKE=$PWD/nofs $apply >/dev/null 2>&1 || true
    if [ ! -e "$PWD/nofs/nixarchy/flatsnap.nix" ]; then
      ok "no flatsnap.nix means nothing is copied"
    else
      bad "apply wrote nixarchy/flatsnap.nix with no source file"
    fi

    printf '%s\n' '{ }' > "$HOME/.config/nixarchy/flatsnap.nix"
    newflake "$PWD/withfs"
    NIXARCHY_FLAKE=$PWD/withfs $apply >/dev/null 2>&1 || true
    if staged "$PWD/withfs" nixarchy/flatsnap.nix; then
      ok "flatsnap.nix is copied into the flake and staged"
    else
      bad "flatsnap.nix was not copied or not staged: $(ls "$PWD/withfs/nixarchy" 2>/dev/null | tr '\n' ' ')"
    fi
    rm -f "$HOME/.config/nixarchy/flatsnap.nix"

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

    # A failed rebuild keeps nh's exit code and makes no claim about what
    # changed: nh activates before it sets the profile and the bootloader, so
    # it can fail with the live system already switched. It points at rollback.
    rm -f "$PWD/nh.calls"; rc=0
    NIXARCHY_FLAKE=$PWD/root NH_STUB_RC=3 $apply --yes --no-preview </dev/null >"$PWD/fail.out" 2>&1 || rc=$?
    if [ "$rc" -eq 3 ] && grep -q "nixarchy rollback" "$PWD/fail.out" && ! grep -q "Nothing changed" "$PWD/fail.out"; then
      ok "a failed rebuild exits with nh's code and points at rollback"
    else
      bad "a failed rebuild exited $rc (want 3), or claimed nothing changed, or named no rollback: $(tail -6 "$PWD/fail.out")"
    fi

    # ---- detached, as a supervised user unit (#765 PR 3) -------------------
    # Stubbed like nh, and for the same reason. `systemctl show` answers with
    # $UNIT_STATE as the unit's SubState; everything else is recorded.
    sdcalls=$PWD/sdrun.calls sccalls=$PWD/sctl.calls
    systemd-run() { echo "$*" >> "$sdcalls"; }
    systemctl() {
      case " $* " in
        *" show "*) echo "''${UNIT_STATE:-}" ;;
        *) echo "$*" >> "$sccalls" ;;
      esac
    }
    export sdcalls sccalls
    export -f systemd-run systemctl
    fresh() { rm -f "$PWD/nh.calls" "$sdcalls" "$sccalls"; rc=0; }

    fresh
    NIXARCHY_FLAKE=$PWD/root $apply --detach --yes </dev/null >/dev/null 2>&1 || rc=$?
    if [ "$rc" -eq 0 ] && ! calls \
      && grep -q -- "--unit=nixarchy-rebuild" "$sdcalls" 2>/dev/null \
      && grep -q -- "RemainAfterExit=yes" "$sdcalls" \
      && ! grep -q -- "--collect" "$sdcalls" \
      && grep -q -- "--yes --no-preview" "$sdcalls"; then
      ok "--detach --yes starts the nixarchy-rebuild unit and does not rebuild in-process"
    else
      bad "--detach --yes exited $rc; systemd-run: $(cat "$sdcalls" 2>/dev/null); nh: $(cat "$PWD/nh.calls" 2>/dev/null)"
    fi

    fresh
    NIXARCHY_FLAKE=$PWD/root UNIT_STATE=running $apply --detach --yes </dev/null >"$PWD/busy.out" 2>&1 || rc=$?
    if [ "$rc" -eq 3 ] && grep -q "already running" "$PWD/busy.out" && [ ! -s "$sdcalls" ]; then
      ok "a detached start refuses while a rebuild is running"
    else
      bad "a detached start during a rebuild exited $rc (want 3): $(cat "$PWD/busy.out")"
    fi

    fresh
    NIXARCHY_FLAKE=$PWD/root UNIT_STATE=exited $apply --detach --yes </dev/null >/dev/null 2>&1 || rc=$?
    if [ "$rc" -eq 0 ] && [ -s "$sccalls" ] && [ -s "$sdcalls" ]; then
      ok "a finished unit is cleared before the next detached start"
    else
      bad "a finished unit was not cleared, or no start followed (exit $rc; systemctl: $(cat "$sccalls" 2>/dev/null))"
    fi

    fresh
    NIXARCHY_FLAKE=$PWD/root $apply --detach </dev/null >/dev/null 2>&1 || rc=$?
    if [ "$rc" -eq 2 ] && [ ! -s "$sdcalls" ]; then
      ok "--detach without --yes exits 2: a unit has no terminal to answer"
    else
      bad "--detach without --yes exited $rc (want 2)"
    fi

    fresh
    NIXARCHY_FLAKE=$PWD/root $apply --yes --no-preview </dev/null >/dev/null 2>&1 || rc=$?
    if grep -q -- "--no-nom" "$PWD/nh.calls" 2>/dev/null; then
      ok "off a terminal, nh runs with --no-nom"
    else
      bad "off a terminal nh ran without --no-nom: $(cat "$PWD/nh.calls" 2>/dev/null)"
    fi

    # ---- what the rebuild panel reads (#765 PR 5) -------------------------
    # The stub above answers every `show` with $UNIT_STATE, which was enough
    # while nixarchy-apply asked for one property with --value. This command
    # asks for three at once, so the stub has to answer by key.
    state=${rebuildState}/bin/nixarchy-rebuild-state
    [ -x "$state" ] || { echo "nixarchy-rebuild-state is not where the module builds it" >&2; exit 1; }

    systemctl() {
      case " $* " in
        *" -p SubState "*)
          printf 'SubState=%s\n' "''${UNIT_STATE:-}"
          printf 'Result=%s\n' "''${UNIT_RESULT:-}"
          printf 'ExecMainStatus=%s\n' "''${UNIT_CODE:-0}"
          ;;
        *" show "*) echo "''${UNIT_STATE:-}" ;;
        *) echo "$*" >> "$sccalls" ;;
      esac
    }
    export -f systemctl

    says() {
      got=$(UNIT_STATE="$2" UNIT_RESULT="$3" UNIT_CODE="$4" $state)
      if [ "$got" = "$1" ]; then
        ok "$5"
      else
        bad "$5 -- said $got, wanted $1"
      fi
    }

    says '{"state":"running","exit":0}'   running ""        0 "a running unit reads as running"
    says '{"state":"succeeded","exit":0}' exited  success   0 "a finished unit that succeeded reads as succeeded"
    says '{"state":"failed","exit":3}'    exited  exit-code 3 "a unit that failed AFTER activating keeps nh's exit code"
    says '{"state":"failed","exit":1}'    failed  exit-code 1 "a failed unit reads as failed"
    says '{"state":"idle","exit":0}'      ""      ""        0 "no unit at all reads as idle"

    [ "$fails" -eq 0 ] || exit 1
    touch $out
  ''
