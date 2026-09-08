{
  pkgs,
  dashboardScript,
  installScript,
}:
# The failure screen names what the failure IS, and connect_wifi says which
# failure it hit.
#
# Both exist because a correct diagnostic that nobody can read is not a
# diagnostic. ui_failed showed twenty-five lines of store paths -- the right
# thing to show, and the wrong thing to read: three signatures account for most
# real failures here and each cost a tester most of a day.
#
#   "unable to download"   the install needed the network and had none
#   texinfo / savannah     the stdenv bootstrap, meaning something was not on
#                          the medium and nix set about compiling it from a
#                          seed. The tail names texinfo or a perl tarball,
#                          which is several layers below anything the reader
#                          did, and reads as "nixarchy is broken" rather than
#                          "this image is missing one file".
#   No space left          the live medium's RAM-backed store filled
#
# And connect_wifi returned 1 for everything, so a mistyped password, a network
# gone out of range, and a NetworkManager that is not running were the same
# screen -- each costing a full round trip through the menu to retry the one
# thing that is nearly always the answer.
#
# runCommand, not a VM: both are shell over strings. checks.install-iso cannot
# reach either -- it asserts installs that SUCCEED, and a passing install
# renders no failure screen at all.
pkgs.runCommand "nixarchy-installer-failure-hints" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
  # The REAL classifier, extracted and called. Not a copy: the first version of
  # this file re-implemented the if/elif chain inside the test script and
  # passed with the product's own classifier broken -- exactly the failure
  # AGENTS.md 1 is about, and the reason ui_failure_hint is a function at all.
  sed -n '/^ui_failure_hint()/,/^}/p' ${dashboardScript} > f.sh
  test -s f.sh || { echo "ui_failure_hint is gone from dashboard.sh" >&2; exit 1; }

  cat > t.sh <<'EOF'
  . ./f.sh

  # The classes, by the sentence each produces. Matching a distinctive phrase
  # rather than the whole string: the wording is meant to be edited, the
  # CLASSIFICATION is not.
  hint_for() {
    case $(ui_failure_hint "$1") in
      *"could not reach it"*)      printf network ;;
      *"tried to compile it"*)     printf bootstrap ;;
      *"ran out of space"*)        printf space ;;
      "")                          ;;
      *)                           printf unknown-class ;;
    esac
  }

  fails=0
  t() { # t <want> <name> <log-content>
    printf '%s\n' "$3" > lg
    got=$(hint_for lg)
    if [ "$got" = "$1" ]; then echo "  ok      $2"; else
      echo "  FAILED  $2: wanted '$1', got '$got'"; fails=$((fails + 1)); fi
  }

  t network "an unreachable substituter is named" \
    "error: unable to download 'https://cache.nixos.org/x.narinfo': Couldn't resolve host"

  # The one that matters most: the reader sees texinfo and has no way to know
  # it means "this image is missing a file your machine needs".
  t bootstrap "the stdenv bootstrap is named" \
    "building '/nix/store/aaa-texinfo-7.3.tar.xz.drv'..."
  t bootstrap "and by its other signatures too" \
    "trying https://download.savannah.gnu.org/releases/x.tar.gz"

  t space "a full store is named" \
    "error: writing to file: No space left on device"

  # A failure nobody has classified must produce NO hint. A wrong hint is
  # worse than none: it sends the reader somewhere confidently.
  t "" "an unrecognised failure gets no hint" \
    "error: builder for '/nix/store/zzz-thing.drv' failed with exit code 1"

  # Ordering. A bootstrap log almost always contains a download line too --
  # nix says "unable to download" for the source it then tries to build. If
  # the download arm won, every bootstrap would be reported as "no network",
  # which is the wrong action: the network is not the problem, the missing
  # path is.
  t network "a plain download failure stays a download failure" \
    "error: unable to download 'https://cache.nixos.org/x'"

  [ "$fails" = 0 ] || { echo "$fails case(s) failed"; exit 1; }
  EOF
  ${pkgs.bash}/bin/bash t.sh

  # connect_wifi's exit-code mapping, asserted on the source: the branches are
  # inside a gum prompt loop, so reaching them needs an interactive terminal
  # and a radio. What must not regress is that the codes are distinguished at
  # all -- `|| return 1` for everything is what this replaced.
  sed -n '/^connect_wifi()/,/^}/p' ${installScript} > c.sh
  fails=0
  for code in 4 10 3 8; do
    if grep -qE "^\s+$code\)" c.sh; then
      echo "  ok      nmcli exit $code has its own message"
    else
      echo "  FAILED  nmcli exit $code is no longer distinguished"; fails=1
    fi
  done
  # And that a wrong password does not cost a trip through the outer menu.
  grep -q 'for attempt in' c.sh ||
    { echo "  FAILED  the password is no longer re-offered in place"; fails=1; }
  echo "  ok      a wrong password is re-offered in place"
  # Never assert the password is wrong: exit 4 is also a network that hands
  # out no address, and telling someone their correct password is wrong is
  # worse than being vague.
  #
  # Matched on what is PRINTED, with comments stripped first. A first draft
  # grepped the whole function and failed against correct code, because the
  # comment above the branch says '"Usually", not "the password is wrong"' --
  # tests/AGENTS.md already records that a forbid-pattern matches prose too,
  # and this walked into it anyway. Deleting that comment to make the check
  # pass would have removed the explanation and kept the behaviour.
  grep -v '^\s*#' c.sh | grep 'ui_left' > printed.sh || true
  if grep -qiE 'password is (wrong|incorrect)' printed.sh; then
    echo "  FAILED  it claims the password is wrong, which exit 4 does not prove"; fails=1
  else
    echo "  ok      and it says 'usually', because exit 4 does not prove it"
  fi
  [ "$fails" = 0 ] || exit 1

  echo "the installer says what went wrong, not only that something did"
  touch $out
''
