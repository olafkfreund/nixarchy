# `nixarchy vm <subcommand>` -- disposable MicroVM sandboxes, the user-scoped
# half of #221's "two halves, both wanted". No root, no rebuild:
# `~/.local/state/nixarchy/microvm/<name>/` is the whole state a VM has, and
# creating or destroying one touches nothing this repo's modules manage. The
# declarative half -- machines that autostart at boot -- is
# `programs.nixarchy.services.microvm` (modules/services/microvm.nix, #223).
#
# Its own file rather than another entry in modules/apps.nix's package list,
# same reason as pkgs/dev-init.nix: `checks.microvm-template` has to exercise
# the real command, not a copy of it.
#
# Two behaviours here are load-bearing, both from #221 and both asserted by
# `checks.microvm-template` rather than trusted:
#
#   * `nix build --out-link`, never `nix run`. `nix run` registers no GC
#     root, and a `nix-collect-garbage` while a guest is running takes the
#     store it is 9p-mounted on out from under it -- reads start returning
#     ENOENT for anything not already in page cache. `--out-link` is an
#     indirect root under /nix/var/nix/gcroots/auto, which is what lets `rm`
#     make the root go away simply by removing the link.
#   * A `flock` on the VM's own directory for the life of the qemu process,
#     so a second `run` of the same name refuses instead of two qemus racing
#     over the same 9p-shared hostdir.
#
# The name is never a Nix argument (#221): `run` builds ONE closure per
# template (from this flake, at the revision this system was built from) and
# `exec`s it from inside `~/.local/state/nixarchy/microvm/<name>/` -- that
# directory, not a Nix parameter, is what makes it "alice's shell" instead of
# "bob's". modules/microvm/guest.nix reads the runtime hostname from a file
# dropped there for exactly this reason.
{
  lib,
  writeShellApplication,
  writeText,
  runCommandLocal,
  coreutils,
  gnugrep,
  util-linux,
  self,
}:
let
  templates = import ../data/microvm-templates.nix;

  # `self.rev` is what mkFlake.nix uses to pin the generated installer flake,
  # and it throws on a dirty tree because that pin has to survive forever on
  # an installed machine. This is not that: worst case here is a `nix build`
  # against `main` instead of the exact commit, so `self.dirtyRev` (present
  # once this tree has ANY commit, dirty or not) and a plain "main" fallback
  # both keep evaluation working -- which matters because, unlike
  # mkFlake.nix, this package is evaluated by every ordinary
  # `nixosModules.nixarchy` consumer, including every check in this repo's
  # own flake, not only the installer image.
  rev = self.rev or self.dirtyRev or "main";
  flakeUrl = "github:olafkfreund/nixarchy/${rev}";

  # One file per template plus a tab-separated index -- same shape as
  # pkgs/dev-init.nix's presetDir, and for the same reason: the script then
  # knows nothing about the catalogue beyond "read this directory", so a new
  # template is a change to data/microvm-templates.nix and nothing else.
  templateDir = runCommandLocal "nixarchy-vm-templates" { } ''
    mkdir -p $out
    cp ${
      writeText "index.tsv" (
        lib.concatMapStrings (n: "${n}\t${templates.${n}.label}\t${templates.${n}.note}\n") (
          lib.attrNames templates
        )
      )
    } $out/index.tsv
  '';
in
writeShellApplication {
  name = "nixarchy-vm";
  runtimeInputs = [
    coreutils
    gnugrep
    util-linux # flock
  ];
  # `nix` itself is deliberately not in runtimeInputs: it is the system's
  # own nix, already first on PATH, and pinning a second copy here would be
  # a second place for its version to drift from the one everything else on
  # the machine uses.
  text = ''
        stateDir="''${XDG_STATE_HOME:-$HOME/.local/state}/nixarchy/microvm"
        templates=${templateDir}
        flakeUrl=${lib.escapeShellArg flakeUrl}

        list_templates() {
          echo "Templates:"
          while IFS=$'\t' read -r name label note; do
            printf '  %-10s %s\n' "$name" "$label"
            printf '  %-10s   %s\n' "" "$note"
          done < "$templates/index.tsv"
        }

        template_exists() {
          grep -q "^$1	" "$templates/index.tsv"
        }

        # KVM present and writable -> the real thing. Absent or not (yet) writable
        # -> the -tcg (software CPU) variant, which is slower but boots anywhere,
        # including nixarchy running inside a VM without nested virtualisation.
        # Preflight rather than letting qemu fail: its own message for a missing
        # /dev/kvm ("Could not access KVM kernel module: No such file or
        # directory") reads like a broken install, not an unavailable feature.
        variant() {
          if [ ! -e /dev/kvm ]; then
            cat >&2 <<'EOF'
    nixarchy-vm: /dev/kvm does not exist on this machine.

    Either virtualisation is off in firmware (Intel VT-x / AMD-V), or this is
    itself a VM without nested virtualisation exposed to it. Falling back to
    the software-emulated CPU runner, which works here but is slower.
    EOF
            echo "tcg"
            return
          fi
          if [ ! -w /dev/kvm ]; then
            cat >&2 <<'EOF'
    nixarchy-vm: /dev/kvm exists but is not writable by you.

    You were likely just added to the kvm group -- group membership is read at
    login, so this needs a logout/login (or reboot) to take effect. Falling
    back to the software-emulated CPU runner for this run.
    EOF
            echo "tcg"
            return
          fi
          echo "kvm"
        }

        list_vms() {
          if [ ! -d "$stateDir" ] || [ -z "$(ls -A "$stateDir" 2>/dev/null)" ]; then
            echo "No VMs yet. 'nixarchy vm create <name>' to make one."
            return
          fi
          echo "VMs:"
          for dir in "$stateDir"/*/; do
            [ -d "$dir" ] || continue
            name=$(basename "$dir")
            tmpl=$(cat "$dir/template" 2>/dev/null || echo "?")
            status=stopped
            if [ -e "$dir/.lock" ]; then
              exec 8>"$dir/.lock"
              flock -n 8 || status=running
              exec 8>&-
            fi
            printf '  %-16s template=%-10s %s\n' "$name" "$tmpl" "$status"
          done
        }

        create_vm() {
          name="''${1:?usage: nixarchy vm create <name> [--template t]}"
          shift
          template=shell
          while [ $# -gt 0 ]; do
            case "$1" in
              --template)
                template="''${2:?--template needs a value}"
                shift 2
                ;;
              *)
                echo "nixarchy-vm: unknown argument '$1'" >&2
                exit 1
                ;;
            esac
          done

          case "$name" in
            *[!a-zA-Z0-9_-]*|"")
              echo "nixarchy-vm: name must be letters, digits, '-' or '_'." >&2
              exit 1
              ;;
          esac

          if ! template_exists "$template"; then
            echo "nixarchy-vm: no template '$template'." >&2
            list_templates >&2
            exit 1
          fi

          dir="$stateDir/$name"
          if [ -e "$dir" ]; then
            echo "nixarchy-vm: '$name' already exists." >&2
            exit 1
          fi

          mkdir -p "$dir"
          echo "$template" > "$dir/template"
          echo "$name" > "$dir/hostname"

          echo "Created '$name' from the '$template' template."
          echo "  nixarchy vm run $name"
        }

        run_vm() {
          name="''${1:?usage: nixarchy vm run <name>}"
          dir="$stateDir/$name"
          if [ ! -d "$dir" ]; then
            echo "nixarchy-vm: no VM named '$name'. 'nixarchy vm create $name' first." >&2
            exit 1
          fi
          template=$(cat "$dir/template")

          # Held for the life of this process -- including across the exec below,
          # since a plain `exec N>file` redirection is not close-on-exec. A second
          # `run` of the same name hits this while the first is still attached to
          # the terminal, and refuses instead of two qemus racing over one 9p
          # share and one volume image.
          exec 9>"$dir/.lock"
          if ! flock -n 9; then
            echo "nixarchy-vm: '$name' is already running." >&2
            exit 1
          fi

          attr="microvm-$template"
          [ "$(variant)" = "tcg" ] && attr="$attr-tcg"

          # Never `nix run`: see the header comment on why that would leave this
          # guest's store share unprotected from garbage collection.
          nix build "$flakeUrl#$attr" --out-link "$dir/current"

          echo "$name" > "$dir/hostname"
          cd "$dir"
          exec ./current/bin/microvm-run
        }

        stop_vm() {
          name="''${1:?usage: nixarchy vm stop <name>}"
          dir="$stateDir/$name"
          if [ ! -d "$dir" ] || [ ! -e "$dir/current" ]; then
            echo "nixarchy-vm: no VM named '$name'." >&2
            exit 1
          fi
          ( cd "$dir" && ./current/bin/microvm-shutdown )
        }

        rm_vm() {
          name="''${1:?usage: nixarchy vm rm <name>}"
          dir="$stateDir/$name"
          if [ ! -d "$dir" ]; then
            echo "nixarchy-vm: no VM named '$name'." >&2
            exit 1
          fi
          if [ -e "$dir/.lock" ]; then
            exec 9>"$dir/.lock"
            if ! flock -n 9; then
              echo "nixarchy-vm: '$name' is running -- 'nixarchy vm stop $name' first." >&2
              exit 1
            fi
          fi
          # Removing the directory removes the out-link with it, which is how the
          # GC root goes away -- there is nothing else to clean up.
          rm -rf "$dir"
          echo "Removed '$name'."
        }

        case "''${1:-}" in
          # Always 0: the -tcg fallback in `variant` above means this works on
          # every nixarchy machine, KVM or not, so #226's menu group has
          # nothing to gate on beyond "this command exists".
          --check) exit 0 ;;
          templates|"") list_templates ;;
          list) list_vms ;;
          create) shift; create_vm "$@" ;;
          run) shift; run_vm "$@" ;;
          stop) shift; stop_vm "$@" ;;
          rm) shift; rm_vm "$@" ;;
          -h|--help|help)
            cat <<'USAGE'
    nixarchy vm -- disposable NixOS MicroVMs. No root, no rebuild.

      nixarchy vm templates          List what's available
      nixarchy vm list                List VMs you have created
      nixarchy vm create <name> [--template t]
                                      Make one (default template: shell)
      nixarchy vm run <name>          Build (if needed) and attach -- Ctrl-A X to
                                       leave the console without stopping the VM
      nixarchy vm stop <name>         Ask a running VM to shut down
      nixarchy vm rm <name>           Delete a VM and its state

    A permanent, boot-time machine is a different thing:
      programs.nixarchy.services.microvm.machines.<name> in your own flake.
    USAGE
            ;;
          *)
            echo "nixarchy-vm: unknown subcommand '$1'" >&2
            exit 1
            ;;
        esac
  '';
}
