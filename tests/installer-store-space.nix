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
    touch $out
''
