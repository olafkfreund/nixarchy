{ pkgs, reinstallScript }:
# nixarchy-reinstall-iso's preflights (#482), driven with an environment that
# lies -- the manner of tests/installer-store-space.nix, because it is the
# same failure being refused: this repo's ENOSPC deaths surface three levels
# from the cause, and a 12 GB image build is the biggest single write a user
# can ask this machine for.
#
# Three functions, extracted and driven on their own; then the assertions
# that keep the extraction honest -- that main still calls each one before
# `nix build`, because a probe tested here and wired nowhere would be #133
# again -- and the honesty strings #478 makes non-negotiable: the image is
# not a backup, and every screen that offers it must say what it does not
# carry.
pkgs.runCommand "nixarchy-reinstall-iso" { } ''
  set -o pipefail

  # ------------------------------------------------------------------------
  # check_disk: refuse what will not fit, refuse a tmpfs, and never refuse
  # on a df it could not read.
  # ------------------------------------------------------------------------
  sed -n '/^check_disk()/,/^}/p' ${reinstallScript} > cd.sh
  test -s cd.sh || { echo "check_disk is not in nixarchy-reinstall-iso any more" >&2; exit 1; }

  cat > cdt.sh <<'EOF'
  red() { echo "$1"; }
  . ./cd.sh
  df() {
    [ -n "$DF_LINE" ] || return 1
    printf 'Type 1M-blocks\n%s\n' "$DF_LINE"
  }
  fails=0
  t() {
    want=$1 name=$2 line=$3
    if DF_LINE=$line check_disk /somewhere 12000 "the image" >got 2>&1; then g=proceed; else g=refuse; fi
    if [ "$g" = "$want" ]; then
      echo "  ok      $name ($g)"
    else
      echo "  FAILED  $name: wanted $want, got $g"; sed 's/^/            /' got
      fails=$((fails + 1))
    fi
  }
  t refuse  "8 GB free, 12 GB needed"     "btrfs 8000M"
  t proceed "40 GB free, 12 GB needed"    "btrfs 40000M"
  # A live ISO's store: df's figure is RAM, and 12 GB of build into it takes
  # the machine down. Refused whatever the number says.
  t refuse  "tmpfs with a big number"     "tmpfs 64000M"
  # Tolerance: a probe that cannot read must not invent a refusal.
  t proceed "df answers nothing"          ""
  exit $fails
  EOF
  bash cdt.sh

  # ------------------------------------------------------------------------
  # committed_verdict: the whole truth table, with a git that lies.
  # ------------------------------------------------------------------------
  sed -n '/^committed_verdict()/,/^}/p' ${reinstallScript} > cv.sh
  test -s cv.sh || { echo "committed_verdict is not in nixarchy-reinstall-iso any more" >&2; exit 1; }

  cat > cvt.sh <<'EOF'
  . ./cv.sh
  git() {
    case "$*" in
      *--git-dir*)   [ "$REPO" = 1 ] ;;
      *"rev-parse HEAD"*) [ "$HEAD" = 1 ] ;;
      *porcelain*)   [ "$DIRTY" = 1 ] && echo " M flake.nix"; return 0 ;;
    esac
  }
  fails=0
  t() {
    want=$1 name=$2 repo=$3 head=$4 dirty=$5
    g=$(REPO=$repo HEAD=$head DIRTY=$dirty committed_verdict /etc/nixos)
    if [ "$g" = "$want" ]; then
      echo "  ok      $name -> $g"
    else
      echo "  FAILED  $name: wanted $want, got '$g'"
      fails=$((fails + 1))
    fi
  }
  t repo-missing "no repository at all"        0 0 0
  t no-commit    "repo, staged, never committed" 1 0 0
  t dirty        "commits plus uncommitted edits" 1 1 1
  t clean        "committed tree"                1 1 0
  exit $fails
  EOF
  bash cvt.sh

  # ------------------------------------------------------------------------
  # drift_verdict: the comparison #478 calls the subtlety that must not be
  # skipped -- and the tolerance arm, because an evaluation that failed is
  # not evidence of drift.
  # ------------------------------------------------------------------------
  sed -n '/^drift_verdict()/,/^}/p' ${reinstallScript} > dv.sh
  test -s dv.sh || { echo "drift_verdict is not in nixarchy-reinstall-iso any more" >&2; exit 1; }

  cat > dvt.sh <<'EOF'
  . ./dv.sh
  fails=0
  t() {
    want=$1 name=$2 running=$3 evaluated=$4
    g=$(drift_verdict "$running" "$evaluated")
    if [ "$g" = "$want" ]; then
      echo "  ok      $name -> $g"
    else
      echo "  FAILED  $name: wanted $want, got '$g'"
      fails=$((fails + 1))
    fi
  }
  t clean   "running matches the flake"    /nix/store/aaa-toplevel /nix/store/aaa-toplevel
  t drift   "un-switched or edited config" /nix/store/aaa-toplevel /nix/store/bbb-toplevel
  t unknown "the evaluation failed"        /nix/store/aaa-toplevel ""
  exit $fails
  EOF
  bash dvt.sh

  echo "the three preflights refuse what they must and only that"

  # ------------------------------------------------------------------------
  # The call sites. Function tests stay green with every call deleted, which
  # is the #133 shape: each preflight must run, and run BEFORE `nix build`.
  # `|| true` because stdenv sets pipefail and a no-match grep must reach
  # the named refusal below.
  # ------------------------------------------------------------------------
  build_line=$(grep -n 'nix build "$REINSTALL_ATTR"' ${reinstallScript} | cut -d: -f1 | head -1 || true)
  [ -n "$build_line" ] || { echo "the script no longer builds via REINSTALL_ATTR; retarget this check" >&2; exit 1; }
  for probe in 'check_disk /nix/store' 'committed_verdict "$FLAKE"' 'drift_verdict "$running"'; do
    line=$(grep -n "$probe" ${reinstallScript} | cut -d: -f1 | head -1 || true)
    [ -n "$line" ] || { echo "main() never calls: $probe" >&2; exit 1; }
    [ "$line" -lt "$build_line" ] || {
      echo "$probe runs after the build starts; a preflight there refuses nothing" >&2
      exit 1
    }
  done

  # A drift verdict the user never sees is a warning that did not happen.
  grep -q 'WARNING: the running system is not what' ${reinstallScript} || {
    echo "the drift arm no longer warns in words; #478 says warn, never" >&2
    echo "silently bake a system that differs from the flake beside it" >&2
    exit 1
  }

  # ------------------------------------------------------------------------
  # The honesty strings. #478: a menu row called "Backup" is a trap, and the
  # same applies to the screen the row opens. Each pattern includes the
  # printing call and its opening quote -- match the call, not the string
  # (tests/AGENTS.md), because the script's own comments say all of this too,
  # and a bare grep stayed green with the printed line deleted. Found by
  # breaking it.
  # ------------------------------------------------------------------------
  for claim in \
    'red "It is NOT a backup.' \
    'echo "  It carries no /home, no service state, no secrets' \
    'ERASES the disk it installs to.'; do
    grep -qF "$claim" ${reinstallScript} || {
      echo "the script no longer says: $claim" >&2
      echo "#478 makes that honesty non-negotiable -- the image carries the" >&2
      echo "system and /etc/nixos only, and booting it wipes the target" >&2
      exit 1
    }
  done

  echo "the preflights are wired ahead of the build, and the words are honest"
  touch $out
''
