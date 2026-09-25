{
  pkgs,
  flakeFile,
  testsDir,
}:
# #1000: a test file that no `checks` entry imports is invisible to every gate
# this repository has.
#
# tests/shell-ipc-resolve.nix shipped with #963 and flake.nix named it NOWHERE.
# It had never run -- not in CI, not locally, not once -- until #982 tried to
# register a sibling beside it and found the anchor missing.
#
# build.yml already asserts the other direction: every entry in `checks` is
# built by some workflow that triggers on pull requests (#164/#166). It cannot
# assert this one. A file in tests/ that is in no entry gives it nothing to
# name, so nothing is missing, so nothing fails.
#
# Measured before this was written: 88 tests/*.nix, 87 named in flake.nix, 87
# imports resolving to a real file, 1 unregistered. So this guards recurrence
# rather than fixing a backlog.
pkgs.runCommand "nixarchy-test-registration"
  {
    inherit flakeFile;
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
  }
  ''
    # Helpers and fixtures, each with the reason it is not a check. The shape
    # cache-allowlist.sh uses: an exemption that does not say why is one nobody
    # can re-judge later.
    #
    #   with-vm-cleanup.nix  a helper, imported by install, install-encrypted,
    #                        free-space and install-teardown rather than
    #                        registered under checks.
    exempt="with-vm-cleanup.nix"

    files=$(cd ${testsDir} && ls *.nix | sort)
    # `import ./tests/<name>.nix`, not a bare filename: a grep for the name
    # passes if it appears in a COMMENT, and whether the file is IMPORTED is
    # the property. This misses a check that built its path dynamically;
    # nothing does, and this comment is cheaper than handling it.
    imports=$(grep -oE 'import \./tests/[a-z0-9-]+\.nix' "$flakeFile" |
      sed 's|import \./tests/||' | sort -u)

    n=$(printf '%s\n' "$imports" | grep -c . || true)
    # A parse that matches nothing would flag all 88 files, and one that
    # over-matched would accept everything and pass having checked nothing.
    # Refuse on an implausible count rather than report one -- #949's
    # agent-id comparison is the precedent, and readme-counts.sh refuses at
    # zero for the same reason.
    if [ "$n" -lt 50 ]; then
      # stdout, not >&2: nix prints a failed builder's captured output, and a
      # first version wrote only to stderr -- the build failed with "exit code
      # 1" and nothing else, so the refusal said nothing to whoever hit it.
      echo "::error::found only $n test imports in flake.nix; the parse is broken,"
      echo "  not the registrations. This check is refusing rather than passing."
      exit 1
    fi

    missing=""
    for f in $files; do
      case " $exempt " in *" $f "*) continue ;; esac
      printf '%s\n' "$imports" | grep -qxF "$f" || missing="$missing $f"
    done

    if [ -n "$missing" ]; then
      echo "::error::these tests are imported by no checks entry, so nothing runs them:"
      for f in $missing; do echo "    tests/$f"; done
      echo "  Add a checks.<name> entry in flake.nix, or list the file in this"
      echo "  check's exempt list with the reason it is not a check."
      exit 1
    fi

    mkdir -p $out
    echo "test registration: $n imports, $(printf '%s\n' "$files" | grep -c .) files, $(printf '%s' "$exempt" | wc -w) exempt"
  ''
