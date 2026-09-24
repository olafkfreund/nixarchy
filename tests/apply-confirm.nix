{ inputs, pkgs }:
# #967: ~/.config/nixarchy/{apps,services,advanced}.nix are imported as full
# NixOS modules, so anything running as the user that writes one writes ROOT
# system configuration at the next apply. The only gate was a polkit prompt
# that does not say what it is authorising, or none at all where sudo is
# passwordless.
#
# A runCommand for the same reason tests/apply-imports.nix is one, and built on
# its shape: the script comes out of the module rather than being copied here,
# so it cannot drift from what nixarchy ships, and `nh` is stubbed so the
# rebuild never runs.
#
# The assertion that matters is "did NOT build", not "printed a warning". Any
# message satisfies the second; only the first says the refusal was real, and
# the stub is what makes it observable.
let
  apply = builtins.head (
    builtins.filter (
      p: (p.pname or p.name or "") == "nixarchy-apply"
    ) inputs.self.nixosConfigurations.vm.config.environment.systemPackages
  );
in
pkgs.runCommand "nixarchy-apply-confirm"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      diffutils
      gnugrep
      git
    ];
  }
  ''
    export HOME=$PWD/home
    export XDG_STATE_HOME=$PWD/state
    apply=${apply}/bin/nixarchy-apply
    [ -x "$apply" ] || { echo "nixarchy-apply is not where the module builds it" >&2; exit 1; }

    # The flake has to be complete enough that apply REACHES the rebuild.
    # A bare flake.nix is not: apply stops at the #734 warning ("nothing
    # imports nixarchy-apps.nix") and never calls nh, so every "did it build"
    # assertion below would read false for a reason that has nothing to do
    # with confirmation. tests/apply-imports.nix builds the same structure.
    host=$(uname -n)
    mkdir -p "$HOME/.config/nixarchy" fake "flake/hosts/$host/nixos"
    cat > flake/flake.nix <<'EOF'
    { outputs = _: { }; }
    EOF
    cat > "flake/hosts/$host/nixos/nixarchy.nix" <<'EOF'
    { imports = [ ../nixarchy-apps.nix ]; }
    EOF
    export NIXARCHY_FLAKE=$PWD/flake

    # "Did it reach the rebuild?" is read from the log, not from a stubbed nh.
    # A stub on PATH cannot work here: writeShellApplication builds a strict
    # PATH from runtimeInputs and prepends it, so the real nh always wins --
    # the property that makes the script hermetic defeats the usual trick.
    #
    # The real nh then fails in the sandbox (no nix), and apply says so. That
    # message is printed ONLY after nh has been invoked, so it is a sound
    # signal for "the rebuild was attempted", which is exactly the line a
    # refusal must not cross.

    # `log`, not `out`: $out is nix's output path and is already in scope here.
    # Capturing apply's output into it made every assertion pass and then broke
    # `mkdir -p $out` -- the derivation failed to produce its own output with
    # nothing in the log to say why.
    say() { printf '{ programs.nixarchy.apps.brave.enable = %s; }\n' "$1" > "$HOME/.config/nixarchy/apps.nix"; }
    built() { printf '%s' "''${log-}" | grep -qi "the rebuild failed"; }
    clean() { log=""; }

    fail() { echo "FAIL: $1" >&2; echo "--- last apply output:" >&2; printf '%s\n' "''${log-}" >&2; exit 1; }

    # 1. No record at all: asked once. No terminal and no --yes, so it refuses
    #    rather than building -- a caller with neither must not get a rebuild.
    say true
    clean
    log=$($apply 2>&1 || true)
    built && fail "first run built an unconfirmed file with no terminal and no --yes"
    grep -qi "not been confirmed" <<<"$log" || fail "first run did not say the file was unconfirmed"

    # 2. The same content with --yes: builds, and records.
    clean
    log=$($apply --yes 2>&1 || true)
    built || fail "--yes did not build a file the user confirmed"

    # 3. Unchanged source, no --yes: SILENT. The property is the absence of a
    #    prompt -- one people see every time is one they dismiss.
    #
    #    Deliberately not asserting that it rebuilds. An apply with nothing to
    #    copy correctly does not rebuild, so requiring one here would encode
    #    apply's bookkeeping rather than this change's behaviour, and would go
    #    red the next time that bookkeeping is made smarter.
    clean
    log=$($apply 2>&1 || true)
    grep -qi "not been confirmed\|changed since" <<<"$log" \
      && fail "an unchanged file prompted; the ordinary apply is supposed to be silent"

    # 4. Changed source, no --yes: REFUSES. This is the issue.
    say false
    clean
    log=$($apply 2>&1 || true)
    built && fail "a changed file was built without confirmation -- this is the bug"
    grep -qi "changed since" <<<"$log" || fail "the refusal did not say the file changed"
    grep -qi "built as root" <<<"$log" || fail "the refusal did not say why it matters"

    # 5. The same change with --yes: builds, and the new content is recorded, so
    #    it does not ask again.
    clean
    log=$($apply --yes 2>&1 || true)
    built || fail "--yes did not build a change the user confirmed"
    #    ...and it does not ask again. Same reasoning as case 3: the property
    #    is the absence of a prompt, not a second rebuild that apply has no
    #    reason to run.
    clean
    log=$($apply 2>&1 || true)
    grep -qi "changed since\|not been confirmed" <<<"$log" \
      && fail "the confirmed change was not recorded; it asked twice"

    mkdir -p $out
    echo "apply confirm: 5 cases, all asserted"
  ''
