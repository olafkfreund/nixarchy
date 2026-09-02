# `nixarchy dev init <preset>` -- a fresh folder becomes a working, pinned
# project environment in one command.
#
# A separate file rather than another entry in modules/apps.nix's systemPackages
# list for one reason: flake.nix's `devenv-presets` runner has to invoke the
# real command, not a copy of it. A check that scaffolds a devenv.nix its own
# way proves nothing about the command people actually type.
#
# What this does NOT do is reimplement `devenv init`. Upstream's scaffold writes
# devenv.nix, devenv.yaml and .gitignore, with comments and doc links in it that
# are worth more than anything generated here would be; when upstream changes
# that scaffold, this follows for free. All this adds is flipping the preset's
# lines and calling `devenv allow`.
{
  lib,
  runCommand,
  writeShellApplication,
  writeText,
  coreutils,
  gnugrep,
  gnused,
}:
let
  presets = import ../data/devenv-presets.nix;

  # `lines` is written flush left in the catalogue and indented here, because
  # Nix's '' strings strip the common leading whitespace off every line -- so
  # indentation written into the data file is indentation that silently does not
  # survive. It did not, the first time: the block landed at column zero in the
  # middle of an otherwise tidy scaffold. Two spaces is devenv's own scaffold
  # indentation, and blank lines stay blank rather than becoming trailing space.
  indent =
    text:
    lib.concatMapStrings (l: if l == "" then "\n" else "  ${l}\n") (
      lib.splitString "\n" (lib.removeSuffix "\n" text)
    );

  # One file per preset plus a tab-separated index, rather than the table being
  # spliced into the script as a case statement. The script then has no
  # knowledge of the catalogue at all: adding a preset is a change to
  # data/devenv-presets.nix and nothing else, and the `lines` reach devenv.nix
  # by `cat`, which cannot mangle quoting the way passing them through a shell
  # variable could.
  presetDir = runCommand "nixarchy-devenv-presets" { } (
    ''
      mkdir -p $out
      cp ${
        writeText "index.tsv" (
          lib.concatMapStrings (n: "${n}\t${presets.${n}.label}\t${presets.${n}.note}\n") (
            lib.attrNames presets
          )
        )
      } $out/index.tsv
    ''
    + lib.concatMapStrings (n: ''
      cp ${writeText "${n}.nix" (indent presets.${n}.lines)} $out/${n}.nix
    '') (lib.attrNames presets)
  );
in
writeShellApplication {
  name = "nixarchy-dev-init";
  # devenv is deliberately NOT here. It is an opt-in catalogue entry that
  # bundles its own Nix, and this command is on every nixarchy machine --
  # declaring it would put that closure on machines whose owner never asked for
  # devenv. writeShellApplication PREPENDS runtimeInputs to PATH rather than
  # replacing it, so the user's own devenv is reachable, and the check below
  # answers for the case where there is none.
  runtimeInputs = [
    coreutils
    gnugrep
    gnused
  ];
  text = ''
    presets=${presetDir}

    list() {
      echo "Presets:"
      while IFS=$'\t' read -r name label note; do
        printf '  %-12s %s\n' "$name" "$label"
        printf '  %-12s   %s\n' "" "$note"
      done < "$presets/index.tsv"
      echo
      echo "  nixarchy dev init <preset>"
    }

    case "''${1:-}" in
      ""|-h|--help|help) list; exit 0 ;;
    esac

    preset="$1"
    if [ ! -f "$presets/$preset.nix" ]; then
      echo "nixarchy: no preset '$preset'." >&2
      list >&2
      exit 1
    fi

    if ! command -v devenv >/dev/null 2>&1; then
      echo "nixarchy: devenv is not installed, and this command is a wrapper" >&2
      echo "around it -- there is nothing useful to do without it." >&2
      echo >&2
      echo "It is in the catalogue as a service:" >&2
      echo >&2
      echo "  nixarchy-service-enable devenv && nixarchy apply" >&2
      echo >&2
      echo "or, in your own configuration:" >&2
      echo >&2
      echo "  programs.nixarchy.services.devenv.enable = true;" >&2
      exit 1
    fi

    # A refusal rather than a merge, and the reason is that this command's only
    # editing move is "flip the preset's lines into the scaffold". Against a
    # devenv.nix somebody has been working in, there is no scaffold to flip them
    # into and no honest way to guess where they belong -- so it stops, and the
    # user pastes two lines they can already read.
    if [ -e devenv.nix ]; then
      echo "nixarchy: this directory already has a devenv.nix." >&2
      echo "This command only scaffolds a new project. To add the preset by hand:" >&2
      echo >&2
      sed 's/^/  /' "$presets/$preset.nix" >&2
      exit 1
    fi

    devenv init

    # Upstream's scaffold ships one commented language line -- at 2.2.2,
    # `# languages.rust.enable = true;` under the devenv.sh/languages/ link --
    # which is exactly where a reader looks for this, so the preset takes its
    # place. The fallback is not decoration: the placeholder is a comment in
    # somebody else's template and can be reworded or dropped in any release,
    # and a scaffold that silently gained no preset would be the worst outcome
    # here. Matched on the shape rather than on `rust` so a change of example
    # language does not fall through.
    placeholder='^[[:space:]]*# languages\.[a-z0-9]+\.enable = true;[[:space:]]*$'
    if grep -qE "$placeholder" devenv.nix; then
      # GNU sed: `r` queues the file for after this cycle's output, `d` drops
      # the line itself, so the block lands where the comment was.
      sed -i -E "/$placeholder/{
        r $presets/$preset.nix
        d
      }" devenv.nix
    else
      # Before the closing brace of the attrset, which is the last line that is
      # a bare `}` at column zero.
      close=$(grep -n '^}' devenv.nix | tail -1 | cut -d: -f1)
      head -n "$((close - 1))" devenv.nix > devenv.nix.new
      cat "$presets/$preset.nix" >> devenv.nix.new
      tail -n +"$close" devenv.nix >> devenv.nix.new
      mv devenv.nix.new devenv.nix
    fi

    # The consent step. devenv refuses to activate a directory nobody has
    # allowed, which is correct -- a devenv.nix is code that runs on `cd`. It is
    # not a prompt here because the user typed the command: they asked for this
    # directory to have an environment, in this directory, seconds ago.
    devenv allow

    cat <<EOF

    Scaffolded a $preset project.

      devenv.nix    the environment -- the preset's lines are in it now
      devenv.yaml   which nixpkgs it draws from
      .gitignore    devenv's own scratch directories

    Re-enter the directory to activate it:

      cd "$PWD"

    The first activation needs the network: devenv.yaml names
    github:cachix/devenv-nixpkgs/rolling and those inputs have to be fetched
    once. It will take a while and then never again.

    That first shell also writes devenv.lock. Commit all four files --
    devenv.nix, devenv.yaml, devenv.lock and .gitignore. The lock IS the
    reproducibility: without it committed, this is a project that worked once,
    on your machine, on a Tuesday.

    Two honest limits. This environment lives in the Nix store but in no system
    generation, so nixos-rebuild --rollback does not touch it and 'devenv gc'
    is yours to run. And the options here are devenv's, not nixarchy's: grow the
    file from https://devenv.sh/reference/options/, and for anything needing
    real Nix rather than an option, https://github.com/cachix/devenv/tree/main/examples
    EOF
  '';
}
