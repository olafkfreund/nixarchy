{ pkgs, doctor }:
# The doctor's dynamic-link check, against binaries built to be broken.
#
# No CI machine has a pip wheel missing libGL in its ~/.local/bin, so without
# fixtures every branch of this section would be untested -- the shape §3
# warns about. The fixtures are real ELF: a binary linked against a library
# that is then deleted (the pip-wheel failure), one whose DT_NEEDED names
# libGL.so.1 itself (the exact error the check exists for), a healthy one, a
# foreign one asking for /lib64's loader (a machine with nix-ld off -- the
# sandbox has no /lib64, which is precisely that machine), and a shell script
# that must be passed over in silence.
pkgs.runCommandCC "nixarchy-doctor-ldd"
  {
    nativeBuildInputs = [
      pkgs.gnugrep
      pkgs.patchelf
    ];
  }
  ''
    mkdir -p libdir scan empty
    echo 'int the_answer(void) { return 42; }' > libmissing.c
    cc -shared -Wl,-soname,libmissing.so.1 -o libdir/libmissing.so.1 libmissing.c
    ln -s libmissing.so.1 libdir/libmissing.so

    printf 'int the_answer(void);\nint main(void) { return the_answer(); }\n' > broken.c
    cc -o scan/broken broken.c -L"$PWD/libdir" -lmissing -Wl,--no-as-needed
    # The library is gone; the binary's rpath now points at nothing, which is
    # what a wheel shipping no libGL looks like at run time.
    rm -r libdir

    echo 'int main(void) { return 0; }' > healthy.c
    cc -o scan/healthy healthy.c

    # The headline failure by name: a binary whose NEEDED list says libGL.so.1.
    cp scan/healthy wants-gl
    patchelf --add-needed libGL.so.1 wants-gl

    # A normal Linux binary on a machine where nix-ld provides no loader.
    cp scan/healthy foreign
    patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 foreign

    printf '#!/bin/sh\nexit 0\n' > scan/script
    chmod +x scan/*

    export HOME=$PWD/home USER=tester
    mkdir -p "$HOME"

    args() { ${doctor}/bin/nixarchy-doctor "$@" 2>&1 || true; }
    scan() { NIXARCHY_LDD_SCAN="$PWD/$1" ${doctor}/bin/nixarchy-doctor 2>&1 || true; }

    fails=0
    want() { # <name> <output> <pattern>
      if printf '%s' "$2" | grep -q "$3"; then echo "  ok      $1"
      else echo "  FAILED  $1: no /$3/ in the output"; fails=$((fails + 1)); fi
    }
    wantnot() {
      if printf '%s' "$2" | grep -q "$3"; then
        echo "  FAILED  $1: /$3/ present and should not be"; fails=$((fails + 1))
      else echo "  ok      $1"; fi
    }

    b=$(args scan/broken)
    [ -n "$b" ] || { echo "FAILED: doctor printed nothing at all"; exit 1; }
    want "broken: names the missing soname"        "$b" "libmissing.so.1"
    want "broken: names the option"                "$b" "programs.nix-ld.libraries"
    want "broken: unknown soname gets the lookup"  "$b" "nix-locate"
    want "broken: says to re-login"                "$b" "log out and back in"

    g=$(args wants-gl)
    want "libGL: the headline error is recognised" "$g" "libGL.so.1"
    want "libGL: mapped to its nixpkgs attribute"  "$g" "with pkgs; \[ libGL \]"

    h=$(args scan/healthy)
    want "healthy: reported healthy"               "$h" "finds all its libraries"
    wantnot "healthy: no warning"                  "$h" "cannot load"

    f=$(args foreign)
    want "foreign: the absent loader is named"     "$f" "/lib64/ld-linux-x86-64.so.2, which does not exist"
    want "foreign: nix-ld enable is the fix"       "$f" "programs.nix-ld.enable = true"

    s=$(args scan/script)
    want "script: honestly declined"               "$s" "not an ELF binary"

    n=$(args ./no-such-file)
    want "missing arg: said so"                    "$n" "does not exist"

    r=$(scan scan)
    want "scan: section present"                   "$r" "Prebuilt binaries"
    want "scan: the broken binary fires"           "$r" "libmissing.so.1"
    wantnot "scan: scripts stay silent"            "$r" "not an ELF binary"
    wantnot "scan: does not claim all is fine"     "$r" "find their libraries"

    e=$(scan empty)
    want "empty scope: says it cannot answer"      "$e" "No ELF binaries in"
    want "empty scope: offers the arg form"        "$e" "nixarchy-doctor <path-or-command>"

    [ "$fails" -eq 0 ] || { echo "$fails assertion(s) failed"; exit 1; }
    touch $out
  ''
