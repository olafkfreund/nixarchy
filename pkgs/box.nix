# `nixarchy box <subcommand>` -- the imperative half of #230's "two halves,
# both wanted". Boxes you are playing with are made on the spot and thrown
# away; boxes you decide to keep get `nixarchy box promote`d into
# `programs.nixarchy.services.boxes.machines.<name>` (modules/services/boxes.nix,
# #257) and roll back with a generation like everything else declared. What
# this command never does is apply that option itself -- it only prints the
# snippet, the same way `nixarchy dev init` never edits a flake for you.
#
# Its own file for the same reason as pkgs/dev-init.nix and pkgs/microvm.nix:
# `checks.box-template` has to exercise the real command, not a copy of it.
#
# THE RULE THIS FILE MUST NOT BREAK (from #256, verified there with
# `distrobox --dry-run`): distrobox resolves its own support binaries
# (distrobox-init, distrobox-export, distrobox-assemble's own callees...)
# relative to `dirname "$0"`. Calling any of them through a literal
# /nix/store/... path bakes a generation-specific path into every container
# they touch, and `nix-collect-garbage` can delete that path out from under a
# running box (nixpkgs#478154). So: no `distrobox` or `distrobox-assemble` in
# runtimeInputs below, and no `${pkgs.distrobox}/bin/...` anywhere in `text`.
# Both are called by bare name, resolved through
# /run/current-system/sw/bin -- which `environment.systemPackages` in
# modules/services/boxes.nix already puts on PATH when this feature is on.
# `checks.box-template` greps for both mistakes directly.
{
  lib,
  writeShellApplication,
  writeText,
  runCommandLocal,
  coreutils,
  gnugrep,
}:
let
  templates = import ../data/box-templates.nix;

  # One file per template's raw INI body plus a tab-separated index -- same
  # shape as pkgs/dev-init.nix's presetDir and pkgs/microvm.nix's
  # templateDir, for the same reason: the script then knows nothing about the
  # catalogue beyond "read this directory", so a new template (#259) is a
  # change to data/box-templates.nix and nothing else.
  templateDir = runCommandLocal "nixarchy-box-templates" { } (
    ''
      mkdir -p $out
      cp ${
        writeText "index.tsv" (
          lib.concatMapStrings (n: "${n}\t${templates.${n}.label}\t${templates.${n}.note}\n") (
            lib.attrNames templates
          )
        )
      } $out/index.tsv
    ''
    + lib.concatMapStrings (n: ''
      cp ${writeText "${n}.ini" templates.${n}.ini} $out/${n}.ini
    '') (lib.attrNames templates)
  );
in
writeShellApplication {
  name = "nixarchy-box";
  # distrobox is deliberately NOT here -- see the header. coreutils/gnugrep
  # are this script's own tools, not distrobox's, so they are safe to pin.
  runtimeInputs = [
    coreutils
    gnugrep
  ];
  text = ''
    templates=${templateDir}

    list_templates() {
      echo "Templates:"
      while IFS=$'\t' read -r name label note; do
        printf '  %-10s %s\n' "$name" "$label"
        printf '  %-10s   %s\n' "" "$note"
      done < "$templates/index.tsv"
      echo
      echo "  nixarchy box create <name> --template <t>"
    }

    template_exists() {
      grep -q "^$1	" "$templates/index.tsv"
    }

    require_distrobox() {
      if ! command -v distrobox >/dev/null 2>&1; then
        cat >&2 <<'EOF'
    nixarchy-box: distrobox is not on PATH.

    Boxes need programs.nixarchy.services.boxes.enable = true; in your own
    configuration -- see docs/manual/boxes.md.
    EOF
        exit 1
      fi
    }

    list_boxes() {
      require_distrobox
      distrobox list
    }

    create_box() {
      name="''${1:?usage: nixarchy box create <name> [--template t]}"
      shift
      template=archlinux
      while [ $# -gt 0 ]; do
        case "$1" in
          --template)
            template="''${2:?--template needs a value}"
            shift 2
            ;;
          *)
            echo "nixarchy-box: unknown argument '$1'" >&2
            exit 1
            ;;
        esac
      done

      if ! template_exists "$template"; then
        echo "nixarchy-box: no template '$template'." >&2
        list_templates >&2
        exit 1
      fi

      require_distrobox

      # distrobox-assemble reads an INI keyed by container name -- the
      # catalogue stores only the body, so a section header naming this box
      # is stitched on here. Called by bare name (the header's rule); the
      # image itself is pulled by podman at this point, over the real
      # network -- the one step checks.box-template deliberately does not
      # attempt (see that file).
      tmp=$(mktemp)
      trap 'rm -f "$tmp"' EXIT
      {
        echo "[$name]"
        cat "$templates/$template.ini"
      } > "$tmp"
      distrobox-assemble create --file "$tmp"

      echo "Created '$name' from the '$template' template."
      echo "  nixarchy box enter $name"
    }

    enter_box() {
      name="''${1:?usage: nixarchy box enter <name>}"
      require_distrobox
      exec distrobox enter "$name"
    }

    rm_box() {
      name="''${1:?usage: nixarchy box rm <name>}"
      require_distrobox
      distrobox rm --yes "$name"
    }

    promote_box() {
      name="''${1:?usage: nixarchy box promote <name>}"
      require_distrobox
      image=$(podman inspect --type container --format '{{.Config.Image}}' "$name" 2>/dev/null) || true
      if [ -z "$image" ]; then
        echo "nixarchy-box: no box named '$name' (podman inspect found nothing)." >&2
        exit 1
      fi
      cat <<EOF
    programs.nixarchy.services.boxes.machines.$name = {
      image = "$image";
      # Add whatever else this box needs -- additional_packages, init_hooks,
      # exported_apps -- see distrobox-assemble's manual. This snippet only
      # knows what podman recorded for the image; nothing else about how
      # '$name' was set up by hand is knowable after the fact -- that is the
      # whole point of promoting it: from here on it is declared instead.
    EOF
      echo "};"
    }

    case "''${1:-}" in
      # Whether this login can actually use boxes right now -- the runtime
      # gate trigger.box's menu group checks itself (#260), since that is
      # only knowable now, not at rebuild time.
      --check)
        command -v distrobox >/dev/null 2>&1
        ;;
      templates|"") list_templates ;;
      list) list_boxes ;;
      create) shift; create_box "$@" ;;
      enter) shift; enter_box "$@" ;;
      rm) shift; rm_box "$@" ;;
      promote) shift; promote_box "$@" ;;
      -h|--help|help)
        cat <<'USAGE'
    nixarchy box -- distrobox, for software NixOS will not run. Not a
    sandbox -- see docs/manual/boxes.md for what that means.

      nixarchy box templates              List what's available
      nixarchy box list                   Boxes distrobox already knows about
      nixarchy box create <name> [--template t]
                                           Make one (default template: archlinux)
      nixarchy box enter <name>           Get a shell in it
      nixarchy box rm <name>              Delete it
      nixarchy box promote <name>         Print the machines.<name> snippet
                                           for a box you decide to keep

    A box that survives a rebuild is a different thing:
      programs.nixarchy.services.boxes.machines.<name> in your own flake.
    USAGE
        ;;
      *)
        echo "nixarchy-box: unknown subcommand '$1'" >&2
        exit 1
        ;;
    esac
  '';
}
