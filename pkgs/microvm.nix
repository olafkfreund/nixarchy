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
  jq,
  dtach,
  systemd,
  self,
}:
let
  templates = import ../data/microvm-templates.nix;

  # `self.rev` is what mkFlake.nix uses to pin the generated installer flake,
  # and it throws on a dirty tree because that pin has to survive forever on
  # an installed machine. This is not that -- unlike mkFlake.nix, this
  # package is evaluated by every ordinary `nixosModules.nixarchy` consumer,
  # including every check in this repo's own flake, so evaluation has to keep
  # working with no rev at all, dirty tree included.
  #
  # On a dirty tree there is no `self.rev`, only `self.dirtyRev`: the
  # underlying commit with "-dirty" appended, which is NOT a ref GitHub can
  # resolve -- handed to `nix build github:...` verbatim it 404s at `run`
  # time, with nix's fetch error as the only word on why. So the suffix is
  # stripped and the underlying commit pinned instead. Even a clean rev is a
  # promise rather than a guarantee -- a commit never pushed resolves no
  # better -- which is why run_vm below falls back to `main`, out loud, when
  # the pinned rev cannot be fetched. Worst case is therefore a `nix build`
  # against `main` instead of the exact commit, and the user is told so.
  # checks.microvm-template asserts both halves, on a pinned fake dirtyRev
  # rather than whatever state CI's checkout happens to be in.
  rev = lib.removeSuffix "-dirty" (self.rev or self.dirtyRev or "main");
  flakeUrl = "github:olafkfreund/nixarchy/${rev}";
  fallbackUrl = "github:olafkfreund/nixarchy/main";

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
    jq # --json output, never assembled by string concatenation (#762)
    dtach # the detached console behind `run --detach` and `console`
    systemd # systemd-run --user, which owns a detached VM's runner
  ];
  # `nix` itself is deliberately not in runtimeInputs: it is the system's
  # own nix, already first on PATH, and pinning a second copy here would be
  # a second place for its version to drift from the one everything else on
  # the machine uses.
  text = ''
        stateDir="''${XDG_STATE_HOME:-$HOME/.local/state}/nixarchy/microvm"
        templates=${templateDir}
        flakeUrl=${lib.escapeShellArg flakeUrl}
        fallbackUrl=${lib.escapeShellArg fallbackUrl}

        list_templates() {
          if [ "''${1:-}" = --json ]; then
            jq -R -s 'split("\n") | map(select(length > 0) | split("\t") | {name: .[0], label: .[1], note: .[2]})' \
              < "$templates/index.tsv"
            return
          fi
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

        # "running" or "stopped", from the same flock the runner holds.
        vm_status() {
          local status=stopped
          if [ -e "$1/.lock" ]; then
            exec 8>"$1/.lock"
            flock -n 8 || status=running
            exec 8>&-
          fi
          echo "$status"
        }

        list_vms() {
          # Fields are only ever added: nixarchy.microvm reads this (#762).
          if [ "''${1:-}" = --json ]; then
            for dir in "$stateDir"/*/; do
              [ -d "$dir" ] || continue
              dir=''${dir%/}
              jq -n --arg name "$(basename "$dir")" \
                --arg template "$(cat "$dir/template" 2>/dev/null || echo "?")" \
                --argjson running "$([ "$(vm_status "$dir")" = running ] && echo true || echo false)" \
                --arg dir "$dir" \
                '{name: $name, template: $template, running: $running, dir: $dir}'
            done | jq -s .
            return
          fi
          if [ ! -d "$stateDir" ] || [ -z "$(ls -A "$stateDir" 2>/dev/null)" ]; then
            echo "No VMs yet. 'nixarchy vm create <name>' to make one."
            return
          fi
          echo "VMs:"
          for dir in "$stateDir"/*/; do
            [ -d "$dir" ] || continue
            name=$(basename "$dir")
            tmpl=$(cat "$dir/template" 2>/dev/null || echo "?")
            status=$(vm_status "$dir")
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

        need_vm() {
          name="''${2:?$1}"
          dir="$stateDir/$name"
          if [ ! -d "$dir" ]; then
            echo "nixarchy-vm: no VM named '$name'. 'nixarchy vm create $name' first." >&2
            exit 1
          fi
        }

        build_vm() {
          template=$(cat "$dir/template")
          attr="microvm-$template"
          [ "$(variant)" = "tcg" ] && attr="$attr-tcg"

          # Never `nix run`: see the header comment on why that would leave this
          # guest's store share unprotected from garbage collection.
          #
          # The pinned rev is this system's own commit, but only a commit
          # GitHub actually has can be fetched -- a dirty checkout's stripped
          # rev and an unpushed local commit both fail here. Falling back to
          # main, with a word about it, beats nix's bare fetch error, which
          # says nothing a user can act on.
          #
          # A pure `nix build github:...` cannot see this system's
          # allowUnfree, and nixpkgs' own override for that case
          # (NIXPKGS_ALLOW_UNFREE=1) is read by getEnv, which pure
          # evaluation returns empty. So the variable buys --impure, and
          # nothing else does: the runner then differs from the public one
          # by exactly the unfree packages a template probes for
          # (modules/microvm/templates/agent-claude.nix), and is built here.
          if ! nix build ''${NIXPKGS_ALLOW_UNFREE:+--impure} "$flakeUrl#$attr" --out-link "$dir/current"; then
            [ "$flakeUrl" != "$fallbackUrl" ] || exit 1
            echo "nixarchy-vm: could not build $flakeUrl#$attr." >&2
            echo "This machine was built from a commit GitHub does not have" >&2
            echo "(a dirty checkout, or one never pushed). Falling back to" >&2
            echo "$fallbackUrl -- the template may differ from the commit" >&2
            echo "this system was built from." >&2
            nix build ''${NIXPKGS_ALLOW_UNFREE:+--impure} "$fallbackUrl#$attr" --out-link "$dir/current"
          fi
        }

        # Held for the life of this process -- including across the exec in
        # exec_vm, since a plain `exec N>file` redirection is not
        # close-on-exec. A second `run` of the same name hits this while the
        # first is still up, and refuses instead of two qemus racing over one
        # 9p share and one volume image.
        take_lock() {
          exec 9>"$dir/.lock"
          if ! flock "$@" 9; then
            echo "nixarchy-vm: '$name' is already running." >&2
            exit 1
          fi
        }

        exec_vm() {
          echo "$name" > "$dir/hostname"
          cd "$dir"
          exec ./current/bin/microvm-run
        }

        run_vm() {
          need_vm "usage: nixarchy vm run [--detach] <name>" "$@"
          take_lock -n
          build_vm
          exec_vm
        }

        # The half a detached unit runs: already built, so lock and launch.
        # `-w 5`, not `-n`: detach_vm's start-up poll takes this same lock for
        # an instant, and a refusal then would read as "already running".
        launch_vm() {
          need_vm "usage: nixarchy vm run --prebuilt <name>" "$@"
          take_lock -w 5
          exec_vm
        }

        # Build here, so the build log and a build failure are the caller's;
        # then a user unit owns the runner, inside dtach so `console` can
        # attach later. The unit's process takes the lock, so `rm` still
        # refuses and a second `run` still does. Back only once it holds it.
        detach_vm() {
          need_vm "usage: nixarchy vm run --detach <name>" "$@"
          if [ "$(vm_status "$dir")" = running ]; then
            echo "nixarchy-vm: '$name' is already running." >&2
            exit 1
          fi
          build_vm
          rm -f "$dir/console.sock"
          systemd-run --user --unit="nixarchy-vm-$name" --collect --quiet \
            --setenv=XDG_STATE_HOME="''${XDG_STATE_HOME:-$HOME/.local/state}" \
            -- "$(command -v dtach)" -N "$dir/console.sock" -z \
            "$(readlink -f "$0")" run --prebuilt "$name"
          timeout=''${NIXARCHY_VM_DETACH_TIMEOUT:-30}
          for _ in $(seq 1 $((timeout * 5))); do
            if [ "$(vm_status "$dir")" = running ]; then
              echo "'$name' is running in the background. 'nixarchy vm console $name' to attach."
              return 0
            fi
            sleep 0.2
          done
          echo "nixarchy-vm: '$name' did not start within ''${timeout}s." >&2
          echo "  See: journalctl --user -u nixarchy-vm-$name" >&2
          exit 1
        }

        run_cmd() {
          case "''${1:-}" in
            --detach) shift; detach_vm "$@" ;;
            --prebuilt) shift; launch_vm "$@" ;;
            *) run_vm "$@" ;;
          esac
        }

        console_vm() {
          need_vm "usage: nixarchy vm console <name>" "$@"
          if [ ! -S "$dir/console.sock" ]; then
            echo "nixarchy-vm: '$name' is not detached -- 'nixarchy vm run $name' attaches directly." >&2
            exit 1
          fi
          # Not `exec`: that would skip a shell function, and the check's
          # dtach stub is one.
          dtach -a "$dir/console.sock" -e '^]' -r winch
        }

        set_template() {
          need_vm "usage: nixarchy vm set-template <name> <template> [--keep-volumes]" "$@"
          template="''${2:?usage: nixarchy vm set-template <name> <template> [--keep-volumes]}"
          keep=false
          [ "''${3:-}" = --keep-volumes ] && keep=true
          if ! template_exists "$template"; then
            echo "nixarchy-vm: no template '$template'." >&2
            list_templates >&2
            exit 1
          fi
          exec 9>"$dir/.lock"
          if ! flock -n 9; then
            echo "nixarchy-vm: '$name' is running -- 'nixarchy vm stop $name' first." >&2
            exit 1
          fi
          # A volume belongs to the template that made it: k3s's disk under a
          # node VM is at best dead weight and at worst mounted where the new
          # template puts something else.
          # A loop, not `compgen -G`: writeShellApplication's bash has no
          # completion builtins, and a missing command in an `if` fails open.
          vols=""
          for f in "$dir"/*.img; do
            [ -e "$f" ] && vols="$vols ''${f##*/}"
          done
          if ! $keep && [ -n "$vols" ]; then
            echo "nixarchy-vm: '$name' has volumes made by its '$(cat "$dir/template")' template:$vols" >&2
            echo "  Pass --keep-volumes to switch anyway, or 'nixarchy vm rm $name' and create it again." >&2
            exit 1
          fi
          echo "$template" > "$dir/template"
          echo "'$name' now uses the '$template' template; the next 'nixarchy vm run $name' rebuilds it."
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
          templates) shift; list_templates "$@" ;;
          "") list_templates ;;
          list) shift; list_vms "$@" ;;
          create) shift; create_vm "$@" ;;
          run) shift; run_cmd "$@" ;;
          console) shift; console_vm "$@" ;;
          set-template) shift; set_template "$@" ;;
          stop) shift; stop_vm "$@" ;;
          rm) shift; rm_vm "$@" ;;
          -h|--help|help)
            cat <<'USAGE'
    nixarchy vm -- disposable NixOS MicroVMs. No root, no rebuild.

      nixarchy vm templates [--json] List what's available
      nixarchy vm list [--json]       List VMs you have created
      nixarchy vm create <name> [--template t]
                                      Make one (default template: shell)
      nixarchy vm run [--detach] <name>
                                      Build (if needed) and attach -- Ctrl-A X to
                                       leave the console without stopping the VM.
                                       --detach runs it in the background instead
      nixarchy vm console <name>      Attach to a detached VM -- Ctrl-] leaves it running
      nixarchy vm set-template <name> <template> [--keep-volumes]
                                      Switch a stopped VM's template; the next run rebuilds.
                                       Refuses over existing volumes unless told
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
