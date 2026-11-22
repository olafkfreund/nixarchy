{ pkgs, ... }:
# root-flake.sh, against a stubbed nix and nix-store (#1909).
#
# A self-hosted job roots its flake source and every input, so the host's
# auto-GC cannot collect them mid-job. This only helps if:
#
#   - every path in the archive tree is rooted, nested inputs included, and an
#     input NAMED `path` is not read as a path;
#   - a failing `nix flake archive` fails the step, even when it printed a tree;
#   - an archive with no source path, or with no inputs, is refused;
#   - a path the GC takes between the archive and its root (invalid, or not in
#     --print-roots) is retried, and fails by name if it never sticks;
#   - every job that can land on a self-hosted runner runs the step right after
#     its checkout. A hand-kept list of those jobs would fail open (CLAUDE.md §4).
let
  tree = builtins.toJSON {
    path = "/nix/store/aaa-source";
    inputs = {
      nixpkgs = {
        path = "/nix/store/bbb-source";
        inputs = { };
      };
      hypr = {
        path = "/nix/store/ccc-source";
        inputs.sub = {
          path = "/nix/store/ddd-source";
          inputs = { };
        };
      };
      # An input named `path`: a walk over every object reads it as one.
      path = {
        path = "/nix/store/eee-source";
        inputs = { };
      };
    };
  };
  noSource = builtins.toJSON {
    inputs = {
      a.path = "/nix/store/bbb-source";
      b.path = "/nix/store/ccc-source";
    };
  };
  noInputs = builtins.toJSON {
    path = "/nix/store/aaa-source";
    inputs = { };
  };

  # Prints $FIXTURE and exits $ARCHIVE_RC.
  nixStub = pkgs.writeShellScript "nix" ''
    [ "$*" = "flake archive --json ." ] || { echo "unexpected nix $*" >&2; exit 9; }
    cat "$FIXTURE"
    exit "''${ARCHIVE_RC:-0}"
  '';

  # Records roots in $STATE/roots. $MODE makes $BAD invalid or unlisted, once or always.
  nixStoreStub = pkgs.writeShellScript "nix-store" ''
    seen() { [ -e "$STATE/seen-$1" ] && return 0; : > "$STATE/seen-$1"; return 1; }
    case "$1" in
      --add-root)
        [ -d "$(dirname "$2")" ] || { echo "no directory for $2" >&2; exit 3; }
        [ "$3" = --realise ] || exit 9
        echo "$2 $4" >> "$STATE/roots"
        echo "$4" ;;
      --gc)
        [ "$2" = --print-roots ] || exit 9
        touch "$STATE/roots"
        while read -r link target; do
          if [ "$target" = "$BAD" ]; then
            case "$MODE" in
              unlisted-always) continue ;;
              unlisted-once) seen unlisted && : || continue ;;
            esac
          fi
          printf '"%s" -> %s\n' "$link" "$target"
        done < "$STATE/roots" ;;
      --check-validity)
        if [ "$2" = "$BAD" ]; then
          case "$MODE" in
            invalid-always) exit 1 ;;
            invalid-once) seen invalid || exit 1 ;;
          esac
        fi ;;
      *) echo "unexpected nix-store $*" >&2; exit 9 ;;
    esac
  '';

  # A job is hosted only when its runs-on is a literal hosted label; a list or an
  # expression can land on p620 (install-check's install job chooses at run time).
  coverage =
    pkgs.writers.writePython3 "root-flake-coverage" { libraries = [ pkgs.python3Packages.pyyaml ]; }
      ''
        import pathlib
        import sys
        import yaml

        HOSTED = ("ubuntu-", "macos-", "windows-")
        missing = []
        for wf in sorted(pathlib.Path(sys.argv[1]).glob("*.yml")):
            jobs = yaml.safe_load(wf.read_text()).get("jobs") or {}
            for name, job in jobs.items():
                runs_on = job.get("runs-on")
                if isinstance(runs_on, str) and runs_on.startswith(HOSTED):
                    continue
                steps = job.get("steps") or []
                for i, step in enumerate(steps):
                    uses = str(step.get("uses", ""))
                    with_ = step.get("with") or {}
                    if not uses.startswith("actions/checkout@"):
                        continue
                    if "repository" in with_ or "path" in with_:
                        continue
                    after = steps[i + 1] if i + 1 < len(steps) else {}
                    if "root-flake.sh" not in str(after.get("run", "")):
                        missing.append(f"{wf.name}: {name}")
                    break
        for m in missing:
            print(f"FAILED {m}: a self-hosted checkout with no root-flake.sh")
        sys.exit(1 if missing else 0)
      '';
in
pkgs.runCommand "nixarchy-root-flake"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      gnused
      jq
    ];
    script = ../.github/scripts/root-flake.sh;
    workflows = ../.github/workflows;
    inherit tree noSource noInputs;
    passAsFile = [
      "tree"
      "noSource"
      "noInputs"
    ];
  }
  ''
    mkdir stubs
    ln -s ${nixStub} stubs/nix
    ln -s ${nixStoreStub} stubs/nix-store
    export PATH=$PWD/stubs:$PATH
    fail=0

    # run <case> <fixture> [VAR=value...]: a fresh state and directory per case.
    run() {
      local name=$1 fixture=$2
      shift 2
      rm -rf "st-$name" "roots-$name"
      mkdir "st-$name"
      env STATE="$PWD/st-$name" FIXTURE="$fixture" MODE= BAD= "$@" \
        bash "$script" "$PWD/roots-$name/dir" > "out-$name" 2>&1
    }
    rooted() { cut -d' ' -f2 "st-$1/roots" 2>/dev/null | sort -u | tr '\n' ' '; }
    want="/nix/store/aaa-source /nix/store/bbb-source /nix/store/ccc-source /nix/store/ddd-source /nix/store/eee-source "
    bad() { echo "FAILED $1"; sed 's/^/    /' "out-$2"; fail=1; }

    run ok "$treePath" && [ "$(rooted ok)" = "$want" ] ||
      bad "every path in the tree, and nothing else, is rooted (rooted: $(rooted ok))" ok

    run archive-fails "$treePath" ARCHIVE_RC=1 && bad "a failing nix flake archive fails the step" archive-fails
    [ -z "$(rooted archive-fails)" ] || bad "a failing archive roots nothing (rooted: $(rooted archive-fails))" archive-fails

    run no-source "$noSourcePath" && bad "an archive with no source path is refused" no-source
    run no-inputs "$noInputsPath" && bad "an archive with no inputs is refused" no-inputs

    run invalid-once "$treePath" MODE=invalid-once BAD=/nix/store/ccc-source ||
      bad "a path invalid once is retried and passes" invalid-once
    run invalid-always "$treePath" MODE=invalid-always BAD=/nix/store/ccc-source &&
      bad "a path that never stays valid fails the step" invalid-always
    grep -q 'ccc-source' out-invalid-always || bad "the failure names the invalid path" invalid-always

    run unlisted-once "$treePath" MODE=unlisted-once BAD=/nix/store/ccc-source ||
      bad "a root missing from --print-roots once is retried and passes" unlisted-once
    run unlisted-always "$treePath" MODE=unlisted-always BAD=/nix/store/ccc-source &&
      bad "a root the daemon never lists fails the step" unlisted-always
    grep -q 'ccc-source' out-unlisted-always || bad "the failure names the unrooted path" unlisted-always

    ${coverage} "$workflows" || fail=1

    [ "$fail" = 0 ] || exit 1
    echo "root-flake: all cases pass"
    touch $out
  ''
