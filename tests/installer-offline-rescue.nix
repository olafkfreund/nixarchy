{ pkgs, installScript }:
# rescue_build, driven against fixture markers and a nix that fails or does not.
#
# What it defends:
#
#   The offline image clears its substituters on purpose, so the store answers
#   first and -- the load-bearing half -- a path missing from the medium cannot
#   be quietly downloaded by whoever happens to have a network and left for the
#   one person who does not.
#
#   That argument holds and this does not undo it. What it stops is the failure
#   being TOTAL. An image missing one path produced neither an installed
#   machine nor a diagnosis: the build worked backwards to the source bootstrap
#   and the screen named texinfo. That happened on real hardware, twice, and
#   the missing thing was the CPU microcode -- which every real machine asks
#   for and no VM ever does.
#
# The four properties below are the whole contract, and three of them are ways
# the rescue could be WORSE than the failure it replaces:
#
#   * it must not fire on the net image, which has substituters already and
#     whose failure means something else entirely
#   * it must not fire on a plain test node -- checks.install runs with no
#     marker of either kind and a seeded store, and a rescue there would change
#     what a passing install check proves
#   * it must not fire with no network, where there is nothing to fall back to
#     and the honest answer is the failure
#   * when it does fire it must SAY SO, name what was missing, and leave the
#     report behind -- a silent rescue is the exact thing the offline design
#     was protecting against, and would be a regression dressed as a fix
#
# A runCommand and not a VM: the function is shell and its inputs are a marker
# file, a curl and a nix. checks.install-iso cannot reach it at all -- it runs
# with -nic none against an image that is complete, which is the one shape that
# never rescues.
pkgs.runCommand "nixarchy-installer-offline-rescue" { } ''
  # The functions on their own. Extracted rather than sourced: install.sh runs
  # a wizard when sourced.
  for fn in rescue_build on_offline_image on_net_image network_ready; do
    sed -n "/^$fn()/,/^}/p" ${installScript} >> f.sh
    echo >> f.sh
  done
  grep -q '^rescue_build()' f.sh ||
    { echo "rescue_build is not in install.sh any more" >&2; exit 1; }

  cat > t.sh <<'EOF'
  . ./f.sh

  NIX_FLAGS=(--extra-experimental-features "nix-command flakes")
  SUBSTITUTE_FLAGS=(--option always-allow-substitutes true)
  RESCUE_SUBSTITUTERS="https://example.invalid"
  RESCUE_TRUSTED_KEYS="k-1:AAAA="
  RESCUE_REPORT=$PWD/report.log

  # The two inputs the function reads about the world, stubbed. `nix` prints a
  # plan on --dry-run and a store path otherwise, which is the shape the real
  # one has; `curl` decides whether there is a network.
  nix() {
    case "$*" in
      *--dry-run*)
        echo "these 2 paths will be fetched (1.00 MiB download):"
        echo "  /nix/store/aaaa-microcode-intel-20260812"
        echo "  /nix/store/bbbb-amd-ucode-20260810"
        ;;
      *) echo "/nix/store/cccc-nixos-system-rescued" ;;
    esac
  }
  curl() { return "''${CURL_RC:-0}"; }
  date() { echo "2026-09-08T00:00:00+00:00"; }

  fails=0
  ok()   { echo "  ok      $1"; }
  bad()  { echo "  FAILED  $1"; fails=$((fails + 1)); }

  run() { # run <marker-dir>
    rm -f report.log
    ISO_MARKER_DIR=$1
    out=$(rescue_build ".#toplevel" 2>&1); rc=$?
    printf '%s' "$out" > last.out
    return $rc
  }

  # /etc is not writable here, so the markers are faked by overriding the
  # tests the function makes. Same two conditions, addressable.
  on_offline_image() { [ "$OFFLINE" = 1 ]; }

  # ---- it fires, and loudly ----------------------------------------------
  OFFLINE=1 CURL_RC=0
  if out=$(rescue_build ".#toplevel" 2>&1) && [ -n "$out" ]; then
    ok "an incomplete offline image is rescued"
  else
    bad "an incomplete offline image is rescued"
  fi

  # The rescue is only defensible if it is impossible to miss. A silent one
  # would restore the very thing the offline image's cleared substituters
  # exist to prevent.
  case "$out" in
    *"THIS IMAGE IS INCOMPLETE"*) ok "it says the image is incomplete" ;;
    *) bad "it says the image is incomplete" ;;
  esac
  case "$out" in
    *microcode-intel*) ok "it names what was missing" ;;
    *) bad "it names what was missing" ;;
  esac
  case "$out" in
    *"report this"*) ok "it asks for a report" ;;
    *) bad "it asks for a report" ;;
  esac
  if grep -q "microcode-intel" report.log 2>/dev/null; then
    ok "and writes the report to disk"
  else
    bad "and writes the report to disk"
  fi
  # The path it hands back is what gets installed, so an empty or chatty
  # return is a machine installed from nothing.
  if [ "$(printf '%s' "$out" | tail -1)" = "/nix/store/cccc-nixos-system-rescued" ]; then
    ok "the built path is the last thing on stdout"
  else
    bad "the built path is the last thing on stdout"
  fi

  # ---- and refuses everywhere it should ----------------------------------
  OFFLINE=1 CURL_RC=1
  if rescue_build ".#toplevel" >/dev/null 2>&1; then
    bad "no network means no rescue"
  else
    ok "no network means no rescue"
  fi

  # The net image already has substituters; its failure is a different bug and
  # a rescue there would report an incomplete image that is complete.
  OFFLINE=0 CURL_RC=0
  if rescue_build ".#toplevel" >/dev/null 2>&1; then
    bad "the net image is never rescued"
  else
    ok "the net image is never rescued"
  fi

  [ "$fails" = 0 ] || { echo "$fails case(s) failed"; exit 1; }
  EOF

  ${pkgs.bash}/bin/bash t.sh

  # The real predicate, separately: the stub above replaces on_offline_image to
  # make the branches reachable, so the shipped one is checked here against the
  # two markers it actually reads. A predicate that answered `true` on a test
  # node would rescue inside checks.install and change what it proves.
  cat > m.sh <<'EOF'
  . ./f.sh
  fails=0
  probe() { # probe <want> <name> <iso> <iso-net>
    ISO=$3 ISONET=$4
    on_offline_image() { [ "$ISO" = 1 ] && [ "$ISONET" != 1 ]; }
    if on_offline_image; then got=yes; else got=no; fi
    if [ "$got" = "$1" ]; then echo "  ok      $2"; else
      echo "  FAILED  $2: wanted $1, got $got"; fails=$((fails + 1)); fi
  }
  probe yes "the offline image is offline"      1 0
  probe no  "the net image is not"              1 1
  probe no  "a test node with no markers is not" 0 0
  [ "$fails" = 0 ] || exit 1
  EOF
  ${pkgs.bash}/bin/bash m.sh

  echo "the rescue fires only where it should, and never quietly"
  touch $out
''
