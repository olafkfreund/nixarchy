{ pkgs, explain }:
# The error explainer, against errors Nix actually emits in this check.
#
# Not one fixture is a pasted string. Every family below is produced here, by
# making Nix fail the way a user makes it fail, and the explainer is fed
# whatever comes out. A pasted trace goes stale silently -- nixpkgs reworded
# the buildEnv collision from "collision between" to "conflicting subpath"
# and reworded the untracked-file error entirely, and a fixture file would
# have kept both checks green while the explainer stopped recognising what
# the machine in front of the user prints.
#
# Each family is asserted twice, and the first assertion is the one that
# matters: `raw` checks that the fixture STILL produces the Nix message it
# was written for. Without it, a fixture that quietly starts succeeding
# leaves the explainer reading an empty string, and "nothing recognised" is
# indistinguishable from "nothing to recognise". Then `want` checks that the
# explainer said the nixarchy-specific thing.
#
# Nested nix: eval only, into a private store and state dir. Nothing is
# built and nothing is fetched -- ${pkgs.path} is already an input, so full
# nixpkgs evaluation is available offline in the sandbox.
pkgs.runCommand "nixarchy-explain"
  {
    nativeBuildInputs = [
      pkgs.nix
      pkgs.git
      pkgs.perl
      pkgs.gnugrep
      pkgs.gnused
    ];
  }
  ''
    # NIXPKGS_ALLOW_UNFREE and NIXPKGS_ALLOW_INSECURE are read by check-meta
    # through builtins.getEnv, so an interactive shell that exports them (a
    # nixarchy desktop does) makes the unfree fixtures silently succeed. The
    # sandbox does not carry them; setting them to 0 says so out loud, and is
    # what makes this check reproduce outside one.
    export HOME=$PWD/home
    export NIX_STORE_DIR=$PWD/nix-store NIX_STATE_DIR=$PWD/nix-state NIX_LOG_DIR=$PWD/nix-log
    export NIXPKGS_ALLOW_UNFREE=0 NIXPKGS_ALLOW_INSECURE=0
    export NIX_CONFIG="experimental-features = nix-command flakes"
    mkdir -p "$HOME"

    lib=${pkgs.path}/lib
    nixpkgs=${pkgs.path}

    fails=0
    # Short variable names here, and none of them called `out`: a shell
    # variable named out clobbers the derivation's own $out, and the build
    # then fails with "failed to produce output path" long after every
    # assertion has printed green, which reads as a store problem.
    want() { # <name> <text> <pattern>
      if printf '%s' "$2" | grep -qF -- "$3"; then echo "  ok       $1"
      else echo "  FAILED   $1: no '$3' in the explanation"; fails=$((fails + 1)); fi
    }
    wantnot() {
      if printf '%s' "$2" | grep -qF -- "$3"; then
        echo "  FAILED   $1: '$3' present and should not be"; fails=$((fails + 1))
      else echo "  ok       $1"; fi
    }
    raw() { # the fixture still produces the Nix message it was written for
      if printf '%s' "$2" | grep -qF -- "$3"; then echo "  fixture  $1"
      else
        echo "  FAILED   $1: the fixture no longer produces '$3' -- it printed:"
        printf '%s\n' "$2" | sed 's/^/           /' | tail -20
        fails=$((fails + 1))
      fi
    }
    explain() { printf '%s' "$1" | ${explain}/bin/nixarchy-explain 2>&1 || true; }
    evalfail() { nix-instantiate --eval --strict -E "$1" 2>&1 || true; }

    echo "== a file that is not git added =========================="
    # Two spellings, both current on machines running nixarchy: a working
    # tree says "is not tracked by Git", and a pinned rev -- what CI and a
    # `nixos-rebuild` against a locked flake evaluate -- copies only the
    # committed files into the store and says "does not exist" about a file
    # that is plainly there in ls. The second is the one that cost this
    # repository three debugging sessions in a day (AGENTS.md section 5).
    mkdir -p flake && (
      cd flake
      git init -q .
      git config user.email a@example.invalid
      git config user.name fixture
      printf '{ outputs = _: { x = import ./untracked.nix; }; }\n' > flake.nix
      echo 42 > untracked.nix
      git add flake.nix
      git commit -qm fixture
    )
    tree=$(cd flake && nix eval .#x 2>&1 || true)
    raw     "working tree: Nix still says 'not tracked'" "$tree" "is not tracked by Git"
    e=$(explain "$tree")
    want    "working tree: recognised"                   "$e" "not in git"
    want    "working tree: names the file"               "$e" "untracked.nix"
    want    "working tree: git add is the fix"           "$e" "git add"
    want    "working tree: staged is enough"             "$e" "staged is enough"

    rev=$(cd flake && git rev-parse HEAD)
    pinned=$(cd flake && nix eval "git+file://$PWD?rev=$rev"#x 2>&1 || true)
    raw     "pinned rev: the older spelling is produced" "$pinned" "does not exist"
    e=$(explain "$pinned")
    want    "pinned rev: recognised as the same thing"   "$e" "not in git"
    want    "pinned rev: says the file is fine"          "$e" "Nothing is wrong with the file"

    echo "== infinite recursion ===================================="
    r=$(evalfail 'let a = a + 1; in a')
    raw     "the fixture recurses"                       "$r" "infinite recursion encountered"
    e=$(explain "$r")
    want    "recognised"                                 "$e" "defined in terms of itself"
    want    "warns the trace is not the place"           "$e" "rarely where the loop was"
    want    "names the overlay shape"                    "$e" "prev, not final"

    echo "== a module argument nothing passes ======================"
    # The AGENTS.md section 5 trap exactly: a module argument cannot have a ?
    # default, because an absent argument resolves through _module.args
    # rather than by the function default. The trace names lib/modules.nix
    # and nothing the user wrote, which is the whole complaint.
    r=$(evalfail "((import $lib).evalModules { modules = [
          ({ lib, ... }: { options.probe = lib.mkOption { type = lib.types.attrs; default = {}; }; })
          ({ source ? {}, ... }: { probe = source; })
        ]; }).config")
    raw     "the fixture loses the argument"             "$r" "attribute 'source' missing"
    raw     "and the trace names only nixpkgs"           "$r" "lib/modules.nix"
    e=$(explain "$r")
    want    "recognised as a module argument"            "$e" "argument nothing passes it"
    want    "names the argument"                         "$e" "source"
    want    "the fix is the call site"                   "$e" "_module.args.source"
    wantnot "not mistaken for a missing package"         "$e" "not in this nixpkgs"

    echo "== an option that does not exist ========================="
    r=$(evalfail "((import $lib).evalModules { modules = [ { services.nope.enable = true; } ]; }).config")
    raw     "the fixture refuses the option"             "$r" "does not exist"
    e=$(explain "$r")
    want    "recognised"                                 "$e" "That option does not exist"
    want    "names the option"                           "$e" "services"
    want    "offers the picker"                          "$e" "nixarchy search"
    # The ordering guard: this message contains the words "does not exist"
    # too, and a loose pattern for the untracked-file family swallows it.
    wantnot "not mistaken for an untracked file"         "$e" "not in git"

    echo "== a home-manager option in the system config ============"
    r=$(evalfail "((import $lib).evalModules { modules = [ { home.packages = []; } ]; }).config")
    raw     "the fixture refuses it"                     "$r" "does not exist"
    e=$(explain "$r")
    want    "says whose option it really is"             "$e" "home-manager.users"

    echo "== two definitions of one option ========================="
    r=$(evalfail "((import $lib).evalModules { modules = [
          ({ lib, ... }: { options.probe = lib.mkOption { type = lib.types.int; }; })
          { probe = 1; }
          { probe = 2; }
        ]; }).config")
    raw     "the fixture collides"                       "$r" "conflicting definition"
    e=$(explain "$r")
    want    "recognised"                                 "$e" "Two places define the same option"
    want    "names the option"                           "$e" "probe"
    want    "explains that nixarchy already yields"      "$e" "lib.mkDefault"
    want    "warns about nixpkgs.config"                 "$e" "free-form"

    echo "== two packages shipping the same file ==================="
    # Driven through nixpkgs' own buildenv builder rather than a pasted
    # message, because the wording has changed inside nixpkgs at least once.
    # Building a real buildEnv here would need a whole stdenv in the nested
    # store; running the real builder against two fixture trees produces the
    # real message for the price of a perl invocation.
    mkdir -p pkgA/bin pkgB/bin env-res
    echo A > pkgA/bin/hello
    echo B > pkgB/bin/hello
    sed 's|@storeDir@|/nix/store|g' "$nixpkgs/pkgs/build-support/buildenv/builder.pl" > builder.pl
    cat > attrs.json <<JSON
    {"outputs":{"out":"$PWD/env-res"},"extraPrefix":"","pathsToLink":["/"],
     "ignoreCollisions":false,"checkCollisionContents":true,"ignoreSingleFileOutputs":false,
     "chosenOutputs":[{"paths":["$PWD/pkgA"],"priority":5},{"paths":["$PWD/pkgB"],"priority":5}],
     "extraPathsFrom":"","manifest":""}
    JSON
    r=$(NIX_ATTRS_JSON_FILE=$PWD/attrs.json perl builder.pl 2>&1 || true)
    raw     "the real builder collides"                  "$r" "conflicting subpath"
    e=$(explain "$r")
    want    "recognised"                                 "$e" "the same file"
    want    "says nothing is broken"                     "$e" "Nothing is broken"
    want    "offers lowPrio"                             "$e" "lib.lowPrio"
    # The spelling this nixpkgs no longer emits, and every older one still
    # does. Produced by hand precisely because no fixture here can produce
    # it any more -- an unproduceable spelling with no assertion is how a
    # matcher rots unnoticed (AGENTS.md section 3).
    e=$(explain "error: collision between \`/nix/store/a-1/bin/hello' and \`/nix/store/b-1/bin/hello'")
    want    "the older buildEnv wording too"             "$e" "the same file"

    echo "== unfree, and insecure =================================="
    # Hermetic on purpose: a package of our own with an unfree licence,
    # rather than naming a real one whose licence could be relicensed out
    # from under the check.
    r=$(evalfail "let p = import $nixpkgs { system = \"${pkgs.stdenv.hostPlatform.system}\"; config = {}; };
        in (p.stdenvNoCC.mkDerivation { name = \"probe-1.0\"; meta.license = p.lib.licenses.unfree; }).outPath")
    raw     "the fixture is refused"                     "$r" "has an unfree license"
    e=$(explain "$r")
    want    "recognised"                                 "$e" "refusing an unfree package"
    want    "says it is not a failure"                   "$e" "policy refusal, not a failure"
    want    "names the nixarchy option"                  "$e" "programs.nixarchy.allowUnfree = true"
    want    "names the package"                          "$e" "probe-1.0"

    r=$(evalfail "let p = import $nixpkgs { system = \"${pkgs.stdenv.hostPlatform.system}\"; config = {}; };
        in (p.stdenvNoCC.mkDerivation { pname = \"probe\"; version = \"1.0\"; meta.knownVulnerabilities = [ \"probe CVE\" ]; }).outPath")
    raw     "the fixture is marked insecure"             "$r" "is marked as insecure"
    e=$(explain "$r")
    want    "recognised"                                 "$e" "known vulnerability"
    # Both refusals now open with the same sentence, so a matcher keyed on
    # that opening calls every insecure package unfree.
    wantnot "not reported as an unfree package"          "$e" "unfree"
    want    "gives the exact list entry"                 "$e" "permittedInsecurePackages = [ \"probe-1.0\" ]"

    echo "== the wrapper form ======================================"
    # `nixarchy explain -- <command>` is the form that never gets exercised by
    # feeding text to stdin, and it was broken on the first real run: the
    # package is built by writeShellApplication, which wraps the script in
    # `set -o errexit`, so capturing the output of a command that fails --
    # the only kind this form is ever handed -- killed the script before it
    # printed anything. It exited with the wrapped command's status, so it
    # looked exactly like the tool had not run.
    w=$(${explain}/bin/nixarchy-explain -- nix-instantiate --eval -E 'let a = a + 1; in a' 2>&1 || true)
    want    "the command's own output is passed through" "$w" "infinite recursion encountered"
    want    "and then explained"                         "$w" "defined in terms of itself"
    ${explain}/bin/nixarchy-explain -- true > /dev/null 2>&1
    echo "  ok       a command that succeeds is not an error"
    if ${explain}/bin/nixarchy-explain -- nix-instantiate --eval -E 'let a = a + 1; in a' >/dev/null 2>&1; then
      echo "  FAILED   the wrapper must report the command's failure"; fails=$((fails + 1))
    else
      echo "  ok       the wrapper reports the command's failure"
    fi

    echo "== what it does with something it cannot place ==========="
    # A recogniser that recognises everything is a horoscope. This asserts
    # the explainer keeps quiet, and reports it in its exit status, on text
    # it has nothing to say about.
    clean=$(evalfail '1 + 1')
    e=$(explain "no space left on device while building /nix/store/x.drv")
    want    "says so rather than guessing"               "$e" "Nothing here matches"
    wantnot "invents no finding"                         "$e" "What to do"
    if printf '%s' "no space left on device" | ${explain}/bin/nixarchy-explain >/dev/null 2>&1; then
      echo "  FAILED   unrecognised input must not exit 0"; fails=$((fails + 1))
    else
      echo "  ok       unrecognised input exits non-zero"
    fi
    raw     "the control fixture really succeeded"       "$clean" "2"

    echo ""
    if [ "$fails" -gt 0 ]; then
      echo "$fails assertion(s) failed"
      exit 1
    fi
    echo "all assertions passed"
    touch $out
  ''
