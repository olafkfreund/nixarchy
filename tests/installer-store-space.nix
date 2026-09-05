{ pkgs, installScript }:
# check_store_space, driven with plans nix really prints and a df that lies.
#
# Its answer selects a build store rather than refusing an install: non-zero
# means "the live store cannot hold this, build into the target instead".
#
# A live ISO's store is a RAM-backed overlay over the squashfs -- half the
# machine's memory. Everything nix fetches or builds lands there before any of
# it reaches the disk, and when it fills the install does not stop: it dies
# partway with "No space left on device", several levels under a "1 dependency
# failed" that names none of it. installer/vm.nix says as much about the test
# VM, which escapes with writableStoreUseTmpfs = false. The ISO cannot.
#
# One user met it as a machine that installed and had no bootloader, and only
# found it by running df himself: 7.8G, 100% used, nothing left.
#
# A fixed threshold would not have caught that. He had 7.8G free when the
# install started, which passes any figure worth setting -- it filled during
# the build. The decision has to come from the size nix itself prints, so this
# checks the parse and the comparison rather than a constant.
#
# A runCommand and not a VM: the function is shell, the inputs are strings, and
# the 25-minute install check cannot see this case at all -- it installs onto a
# machine whose store fits, which is the only shape that does not fail.
pkgs.runCommand "nixarchy-installer-store-space" { } ''
    # The function on its own. Extracting it rather than sourcing install.sh,
    # which runs a wizard when sourced.
    sed -n '/^check_store_space()/,/^}/p' ${installScript} > f.sh
    test -s f.sh || { echo "check_store_space is not in install.sh any more" >&2; exit 1; }

    cat > t.sh <<'EOF'
    . ./f.sh
    # $FREE bytes available, so the comparison is what is under test and not
    # whatever the builder happens to be sitting on.
    df() {
      case "$*" in
        *-B1*) printf 'F 1B-blocks Used Available Cap Mounted\noverlay 8000000000 0 %s 100%% /nix/store\n' "$FREE" ;;
        *)     printf 'F Size Used Avail Cap Mounted\noverlay 7.8G 7.8G 0 100%% /nix/store\n' ;;
      esac
    }
    fails=0
    t() {
      want=$1 name=$2 free=$3 plan=$4
      if FREE=$free check_store_space "$plan" >out 2>&1; then got=proceed; else got=refuse; fi
      if [ "$got" = "$want" ]; then
        echo "  ok      $name ($got)"
      else
        echo "  FAILED  $name: wanted $want, got $got"; sed 's/^/            /' out
        fails=$((fails + 1))
      fi
    }

    GB=1073741824
    FETCH21='these 489 paths will be fetched (8.1 GiB download, 21.0 GiB unpacked):'

    # The reported case: 21 GiB of paths, 7.8G of RAM-backed store.
    t refuse  "21 GiB needed, 7.8G free -> target"      8371830784        "$FETCH21"
    # The same install on a machine with room.
    t proceed "21 GiB needed, 900G free -> live"      $((900 * GB))     "$FETCH21"
    # Units below GiB are parsed too, or a small overflow reads as no overflow.
    t refuse  "120 MiB needed, 100 MiB free"  $((100 * 1048576)) \
      'these 12 paths will be fetched (40.2 MiB download, 120.5 MiB unpacked):'
    # The normal install: the image carries the closure, nothing is fetched.
    t proceed "nothing to fetch"              8371830784        'these 0 derivations will be built'
    # Tolerance. This exists to name a failure that already happens; a plan it
    # cannot read must not become a new way to refuse an install that would work.
    t proceed "unparseable plan"              1                 'some other nix message entirely'
    t proceed "builds, no sizes printed"      1                 'these 4 derivations will be built:'
    exit $fails
  EOF
    bash t.sh

    # And that the target-store fallback asks for a store that will ACCEPT what
  # it is handed.
  #
  # A path built on the installing machine has no signature, and a fresh store
  # refuses unsigned paths -- "cannot add path ... because it lacks a signature
  # by a trusted key". NixOS' own assembly derivations are allowSubstitutes =
  # false, so they are always built and always unsigned; the fallback therefore
  # fails on every real machine without this.
  #
  # Asserted here because nothing else can. tests/install.nix and
  # tests/free-space.nix both set require-sigs = false INSIDE the test VM -- and
  # say why -- so an install check passes whether or not the installer asks for
  # it. The ISO does not set it. That gap is exactly how #251 shipped broken and
  # went green.
  # The URI form, not the bare setting -- the comment above it in install.sh
  # says "require-sigs=false" too, so a looser pattern matches the explanation
  # and stays green with the flag deleted. Found by breaking it.
  grep -q '/mnt?require-sigs=false' ${installScript} || {
    echo "" >&2
    echo "the target-store build does not pass require-sigs=false." >&2
    echo "" >&2
    echo "Paths built on the installing machine are unsigned, and a fresh" >&2
    echo "store rejects them:" >&2
    echo "" >&2
    echo "  cannot add path '...' because it lacks a signature by a trusted key" >&2
    echo "" >&2
    echo "No install check can catch this: they set require-sigs = false in" >&2
    echo "the test VM, so /mnt accepts unsigned paths there regardless." >&2
    exit 1
  }
  grep -q 'eval-store auto' ${installScript} || {
    echo "the target-store build no longer splits the evaluation store; see #249" >&2
    exit 1
  }

  echo "check_store_space refuses what will not fit and nothing else"

  # ------------------------------------------------------------------------
  # preflight_build (#300): the disk must not be wiped before anything proves
  # the build could start. Same doctrine as above -- the function on its own,
  # driven with stubs that lie.
  # ------------------------------------------------------------------------
  sed -n '/^preflight_build()/,/^}/p' ${installScript} > pf.sh
  test -s pf.sh || { echo "preflight_build is not in install.sh any more" >&2; exit 1; }
  grep '^on_net_image()' ${installScript} >> pf.sh

  cat > pt.sh <<'EOF'
  NIX_FLAGS=() SUBSTITUTE_FLAGS=()
  SUBSTITUTERS="https://nixarchy.cachix.org"
  work=/nonexistent hostname=h
  . ./pf.sh
  # The one thing that must never happen before the probes pass.
  wipefs() { touch wipefs-called; }
  git() { :; }
  curl() { [ "$CURL_OK" = 1 ]; }
  nix() {
    if [ "$NIX_OK" = 1 ]; then echo 'these 0 derivations will be built'; else
      # Long on purpose: a real dry-run of a desktop closure is thousands of
      # lines, which is what makes an early-exiting reader (`grep -m1`, `grep
      # -q`) kill its producer with EPIPE -- the #273 shape. A short plan
      # cannot reproduce that race; this one does.
      echo "error: unable to download 'https://github.com/x/archive/r.tar.gz'"
      seq 1 200000 | sed 's/^/error: cascade line /'
      return 1
    fi
  }
  fails=0
  t() {
    want=$1 name=$2 img=$3 curlok=$4 nixok=$5
    if [ "$img" = net ]; then on_net_image() { return 0; }; else on_net_image() { return 1; }; fi
    if CURL_OK=$curlok NIX_OK=$nixok preflight_build >out 2>&1; then got=proceed; else got=refuse; fi
    if [ "$got" = "$want" ]; then
      echo "  ok      $name ($got)"
    else
      echo "  FAILED  $name: wanted $want, got $got"; sed 's/^/            /' out
      fails=$((fails + 1))
    fi
  }

  # No marker: checks.install's shape -- no network, seeded store. Probing
  # here would fail a passing check, so nothing may be probed at all.
  t proceed "no image marker, network dead"      none 0 0
  # The filed case: net image, cache dark. Refused, and the message names
  # the network rather than emitting a dependency cascade.
  t refuse  "net image, substituter unreachable" net  0 1
  grep -qi 'network' out || { echo "  FAILED  refusal does not name the network"; fails=$((fails+1)); }
  # The network died after ask_network let it through: evaluation fails.
  t refuse  "net image, flake input unreachable" net  1 0
  grep -qi 'network' out || { echo "  FAILED  eval refusal does not name the network"; fails=$((fails+1)); }
  # The #273 regression, which reached a user: an early-exiting grep killing
  # its producer puts "printf: Broken pipe" immediately above the refusal, on
  # the one screen where noise costs the most.
  ! grep -qi 'broken pipe' out || { echo "  FAILED  refusal is preceded by Broken pipe noise"; fails=$((fails+1)); }
  # And a network that works installs as before.
  t proceed "net image, everything answers"      net  1 1

  # An ENCRYPTED install must pin the ENCRYPTED module list.
  #
  # reuse_baked_initrd chose between two baked lists on `[ "$encrypt" = "yes" ]`
  # while validate_answers normalises the answers file's yes/no into true/false
  # before any phase runs -- so the encrypted branch was UNREACHABLE and every
  # encrypted install pinned the PLAIN list with mkForce, discarding
  # luksroot.nix's dm_crypt. Install succeeds; machine will not unlock its root.
  # Nothing caught it because every install test in this repo uses encrypt=no.
  #
  # No nested heredoc here on purpose: this is inside a Nix indented string,
  # where the terminator would itself be indented and so would not terminate --
  # the same trap that once swallowed a theme install. (Writing the two-quote
  # delimiter in this comment would also end the string, which is how the first
  # attempt at this comment broke the file.)
  sed -n '/^reuse_baked_initrd()/,/^}/p' ${installScript} > rb.sh
  test -s rb.sh || { echo "reuse_baked_initrd is not in install.sh any more" >&2; exit 1; }
  sed -i 's/@initrdmodules@/ENCRYPTEDLIST ahci/; s/@initrdforced@/ENCFORCED/' rb.sh
  sed -i 's/@initrdmodulesplain@/PLAINLIST ahci/; s/@initrdforcedplain@/PLAINFORCED/' rb.sh

  # Ends with a closing brace: reuse_baked_initrd refuses to touch a file whose
  # last line is not `}`, because the pin has to go inside it.
  printf '{\n  boot.initrd.availableKernelModules = [ "ahci" ];\n  boot.initrd.kernelModules = [ ];\n}\n' > hw.nix
  ( . ./rb.sh; encrypt=true reuse_baked_initrd hw.nix )
  if grep -q ENCRYPTEDLIST hw.nix; then
    echo "  ok      encrypt=true pins the encrypted list"
  else
    echo "  FAILED  encrypt=true pinned the PLAIN list -- LUKS modules mkForce'd away"
    fails=$((fails + 1))
  fi

  # (c) of #300: across every scenario, including the refusals, the disk was
  # never touched.
  [ ! -e wipefs-called ] || { echo "  FAILED  preflight called wipefs"; fails=$((fails+1)); }
  exit $fails
  EOF
  bash pt.sh

  # And that main() actually runs it ahead of the wipe. The function tests
  # above stay green with the call site deleted, which would be #133 again:
  # written, extracted, asserted, and run by nothing.
  # `|| true` because stdenv sets pipefail, and a grep with no match must
  # reach the named refusal below rather than kill the script mid-pipe.
  pf_line=$(grep -n 'preflight_build || exit 1' ${installScript} | cut -d: -f1 | head -1 || true)
  fmt_line=$(grep -n '^    format_disk &&' ${installScript} | cut -d: -f1 | head -1 || true)
  [ -n "$pf_line" ] || { echo "main() no longer calls preflight_build" >&2; exit 1; }
  [ -n "$fmt_line" ] && [ "$pf_line" -lt "$fmt_line" ] || {
    echo "preflight_build does not run before format_disk; #300 is back" >&2; exit 1;
  }

  echo "preflight_build refuses before the wipe, and main runs it there"
    touch $out
''
