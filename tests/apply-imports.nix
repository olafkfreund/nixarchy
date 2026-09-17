{ inputs, pkgs }:
# #734: the "nothing imports it" warning greps for the FILENAME anywhere in the
# flake, so a stale root-level nixarchy-apps.nix satisfies it while the per-host
# file apply just wrote is imported by nobody.
#
# The failure it hides is worse than a missing file. The root copy is still
# imported and still holds the OLD selection, so the app set freezes rather than
# disappearing: apps enabled before the layout changed keep working, apps
# enabled after it never appear, and apply reports success every time. Reported
# against ebe93dd by a user with three hosts all importing ../../../nixarchy-apps.nix.
#
# The variable that separates the two cases is the layout (AGENTS.md 3), and a
# check that only ever ran a root-layout flake could not see this at all -- the
# stale import and the written file are the same path there.
#
# A runCommand, not a VM: the whole bug is which path a grep resolves to. The
# script comes out of the module rather than being copied here, so it cannot
# drift from what nixarchy actually ships.
let
  # The script alone. Taking it from system.build.toplevel would pull a whole
  # desktop closure into the hosted omarchy job, whose runner has ~14 GB of
  # disk -- see tests/apply-staging.nix for what that cost.
  apply = builtins.head (
    builtins.filter (
      p: (p.pname or p.name or "") == "nixarchy-apply"
    ) inputs.self.nixosConfigurations.vm.config.environment.systemPackages
  );
in
pkgs.runCommand "nixarchy-apply-imports"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      git
    ];
  }
  ''
        export HOME=$PWD/home
        apply=${apply}/bin/nixarchy-apply
        [ -x "$apply" ] || { echo "nixarchy-apply is not where the module builds it" >&2; exit 1; }

        # The selection apply reads.
        mkdir -p "$HOME/.config/nixarchy"
        cat > "$HOME/.config/nixarchy/apps.nix" <<'EOF'
    { programs.nixarchy.apps.brave.enable = true; }
    EOF

        # apply ends by rebuilding, which this check has no business doing.
        mkdir -p fake
        printf '#!/bin/sh\nexit 0\n' > fake/nh
        chmod +x fake/nh
        export PATH=$PWD/fake:$PATH

        host=$(uname -n)

        # A flake that predates the per-host layout: the host config imports the
        # ROOT nixarchy-apps.nix, which is what every real report looked like.
        mkdir -p "stale/hosts/$host/nixos"
        cat > stale/flake.nix <<'EOF'
    { outputs = _: { }; }
    EOF
        cat > stale/nixarchy-apps.nix <<'EOF'
    { imports = [ ]; }
    EOF
        cat > "stale/hosts/$host/nixos/nixarchy.nix" <<'EOF'
    { imports = [ ../../../nixarchy-apps.nix ]; }
    EOF

        log=$(NIXARCHY_FLAKE=$PWD/stale $apply 2>&1 || true)

        # apply writes per-host because hosts/<hostname> exists...
        [ -f "stale/hosts/$host/nixarchy-apps.nix" ] || {
          echo "apply did not write the per-host file; this check is testing the wrong thing" >&2
          printf '%s\n' "$log" >&2
          exit 1
        }

        # ...and nothing imports THAT file, so the warning has to fire. Before #734
        # it did not: the root-level import matched the filename and silenced it,
        # which is the bug -- a warning satisfied by the very condition it tests for.
        printf '%s\n' "$log" | grep -q 'WARNING: nothing in' || {
          echo "no warning, although the file apply wrote is imported by nobody." >&2
          echo "A stale root-level nixarchy-apps.nix satisfied a filename match:" >&2
          echo "  written:  stale/hosts/$host/nixarchy-apps.nix" >&2
          echo "  imported: stale/nixarchy-apps.nix (the OLD selection)" >&2
          echo "The app set freezes and apply reports success (#734)." >&2
          printf '%s\n' "$log" >&2
          exit 1
        }
        echo "a stale root-level import no longer satisfies the per-host warning"

        # And the warning must not still be sending people to the root file.
        printf '%s\n' "$log" | grep -q "hosts/$host/nixarchy-apps.nix" || {
          echo "the warning does not name the file apply actually wrote" >&2
          printf '%s\n' "$log" >&2
          exit 1
        }
        echo "the warning names the file that was written, not a root-layout guess"

        # The other half, so the fix cannot be "always warn": a host that imports
        # the per-host file it was given must stay quiet.
        mkdir -p "good/hosts/$host/nixos"
        cat > good/flake.nix <<'EOF'
    { outputs = _: { }; }
    EOF
        cat > "good/hosts/$host/nixos/nixarchy.nix" <<'EOF'
    { imports = [ ../nixarchy-apps.nix ]; }
    EOF

        log=$(NIXARCHY_FLAKE=$PWD/good $apply 2>&1 || true)
        printf '%s\n' "$log" | grep -q 'WARNING: nothing in' && {
          echo "warned although the host imports exactly the file apply wrote" >&2
          printf '%s\n' "$log" >&2
          exit 1
        }
        echo "a host that imports the written file is not warned at"

        touch $out
  ''
