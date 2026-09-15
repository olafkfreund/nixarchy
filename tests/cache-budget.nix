{ pkgs, ... }:
# What reaches nixarchy.cachix.org, and what it costs (#697).
#
# The cache is the free tier: 5 GB, evicted by last download. Every job used to
# push whatever it built and the cache filled with paths nobody downloads, so
# three things now decide what goes in, and each is easy to ship broken in a way
# no build would notice:
#
#   cache-budget.sh      the allowlist's cost -- a UNION of closures, minus what
#                        cache.nixos.org already serves -- and a refusal over
#                        budget. Summing per entry, or counting upstream paths,
#                        reads as "over budget" on a cache that is fine, and the
#                        reverse bug reads as fine on one that is full.
#   cachix-push.sh --proof   one check result, alone. A result with a dependency
#                        would upload a closure; that is how the cache filled.
#   cachix-push.sh       closures from main only.
#
# The scripts are the real files; nix, curl and cachix are stubs over a small
# pretend store described by store.json.
pkgs.runCommand "nixarchy-cache-budget"
  {
    nativeBuildInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      gawk
      findutils
      jq
    ];
    scripts = ../.github/scripts;
  }
  ''
    mkdir -p bin calls
    work=$PWD
    MiB=1048576

    # A pretend store. Each installable names its closure: path -> NAR bytes.
    # /nix/store/up-* paths are served upstream; everything else is ours.
    cat > store.json <<EOF
    {
      ".#small":  { "/nix/store/aaa-small": $((10 * MiB)), "/nix/store/up1-glibc": $((500 * MiB)) },
      ".#other":  { "/nix/store/bbb-other": $((20 * MiB)), "/nix/store/shared-qemu": $((400 * MiB)) },
      ".#twin":   { "/nix/store/ccc-twin":  $((5 * MiB)),  "/nix/store/shared-qemu": $((400 * MiB)) },
      ".#huge":   { "/nix/store/ddd-huge":  $((3000 * MiB)) },
      ".#checks.x86_64-linux.lonely":  { "/nix/store/eee-lonely": 96 },
      ".#checks.x86_64-linux.clingy":  { "/nix/store/fff-clingy": 200, "/nix/store/ggg-dep": 4096 }
    }
    EOF

    # nix: build, eval, path-info -- answered from store.json. A check's
    # "result path" is the first key of its closure.
    cat > bin/nix <<EOF
    #!${pkgs.bash}/bin/bash
    store=$work/store.json
    closure_of() { # installable or store path -> closure object
      jq -c --arg k "\$1" '.[\$k] // (to_entries | map(select(.value | has(\$k))) | first | .value) // empty' "\$store"
    }
    case "\$1 \$2" in
      "build --no-link") closure_of "\$3" | grep -q . ;;
      "build --keep-going") exit 0 ;;
      "eval --raw") jq -r --arg k "\$3" '.[\$k] | keys_unsorted[0]' "\$store" ;;
      "path-info -r")
        if [ "\$3" = --json ]; then closure_of "\$4" | jq -c 'map_values({ narSize: . })'
        else closure_of "\$3" | jq -r 'keys[]'; fi ;;
      path-info*) closure_of "\$2" | grep -q . ;;
      *) echo "stub nix: unexpected \$*" >&2; exit 9 ;;
    esac
    EOF
    # curl: 200 for an up-* narinfo on either upstream, 404 otherwise.
    cat > bin/curl <<EOF
    #!${pkgs.bash}/bin/bash
    url=\''${!#}
    case "\$(basename "\$url")" in up*) printf 200 ;; *) printf 404 ;; esac
    EOF
    # cachix: records what it was asked to push, from stdin or arguments.
    cat > bin/cachix <<EOF
    #!${pkgs.bash}/bin/bash
    shift 2
    if [ \$# -gt 0 ]; then printf '%s\n' "\$@"; else cat; fi >> $work/calls/pushed
    EOF
    chmod +x bin/*
    export PATH=$work/bin:$PATH UPSTREAM_CACHES="https://up.one https://up.two" LOOKUP_JOBS=4
    budget=$scripts/cache-budget.sh
    push=$scripts/cachix-push.sh
    fails=0
    ok()   { echo "  ok      $1"; }
    bad()  { echo "  FAILED  $1"; fails=$((fails + 1)); }

    # (a) Under budget: 10 + 20 + 5 + 400 (shared once) = 435 MiB of 2048.
    if got=$(bash $budget .#small .#other .#twin 2>&1); then
      ok "entries under the budget pass"
    else
      bad "entries under the budget failed:"; printf '%s\n' "$got"
    fi

    # (c) The upstream glibc (500 MiB) is not ours, so .#small alone is 10 MiB.
    got=$(bash $budget .#small 2>&1)
    if grep -q 'in nixarchy.cachix.org: 1 paths, 10 MiB' <<<"$got"; then
      ok "a path served upstream is not counted"
    else
      bad "a path served upstream was counted:"; printf '%s\n' "$got"
    fi

    # (d) other + twin share a 400 MiB path: 425 MiB, never 825.
    got=$(bash $budget .#other .#twin 2>&1)
    if grep -q ', 425 MiB of' <<<"$got"; then
      ok "a path two entries share is counted once"
    else
      bad "a shared path was counted twice:"; printf '%s\n' "$got"
    fi

    # (b) Over budget: fails, and names the entry that pulled it in.
    if got=$(bash $budget .#small .#huge 2>&1); then
      bad "3 GB of allowlist passed a 2 GB budget"
    elif grep -q '::error::the allowlist costs 3010 MiB' <<<"$got" && grep -q 'from .#huge' <<<"$got"; then
      ok "over budget fails, naming the entry that grew"
    else
      bad "over budget failed without naming the entry:"; printf '%s\n' "$got"
    fi

    export CACHIX_AUTH_TOKEN=stub

    # (e) A proof is the result path and nothing else, from any ref.
    rm -f calls/pushed
    GITHUB_REF=refs/pull/1/merge bash $push --proof lonely >/dev/null 2>&1
    if [ "$(cat calls/pushed 2>/dev/null)" = /nix/store/eee-lonely ]; then
      ok "a proof pushes the result path alone, from a pull request"
    else
      bad "the proof of a single-path result pushed: $(cat calls/pushed 2>/dev/null | tr '\n' ' ')"
    fi

    # (f) A result with a dependency would upload a closure: refused, not pushed.
    rm -f calls/pushed
    got=$(GITHUB_REF=refs/heads/main bash $push --proof clingy 2>&1) || true
    if [ ! -s calls/pushed ] && grep -q "clingy's result is 2 paths" <<<"$got"; then
      ok "a result with a dependency is refused as a proof"
    else
      bad "a result with a dependency was pushed as a proof: $(cat calls/pushed 2>/dev/null | tr '\n' ' ')"
    fi

    # (g) Closures: nothing off main, the whole closure on main.
    rm -f calls/pushed
    GITHUB_REF=refs/pull/1/merge bash $push .#other >/dev/null 2>&1
    if [ ! -s calls/pushed ]; then
      ok "a closure is not pushed off main"
    else
      bad "a pull request pushed a closure: $(tr '\n' ' ' < calls/pushed)"
    fi
    GITHUB_REF=refs/heads/main bash $push .#other >/dev/null 2>&1
    if [ "$(sort calls/pushed 2>/dev/null | tr '\n' ' ')" = "/nix/store/bbb-other /nix/store/shared-qemu " ]; then
      ok "main pushes the closure"
    else
      bad "main did not push the closure: $(tr '\n' ' ' < calls/pushed 2>/dev/null)"
    fi

    # (h) build-unless-proven.sh pushes proofs for what it built, and only
    # that. "fresh" is not in the cache; "lonely" is, so it is skipped.
    cat > bin/already-proven-stub <<'EOF'
    #!${pkgs.bash}/bin/bash
    for c in "$@"; do c=''${c#.#checks.x86_64-linux.}; [ "$c" = lonely ] || echo "$c"; done
    EOF
    chmod +x bin/already-proven-stub
    mkdir -p scripts-under-test
    cp $scripts/build-unless-proven.sh $scripts/cachix-push.sh scripts-under-test/
    cp bin/already-proven-stub scripts-under-test/already-proven.sh
    chmod +x scripts-under-test/*
    # The real scripts say #!/usr/bin/env bash, which the sandbox has not got.
    patchShebangs scripts-under-test >/dev/null
    jq '. + { ".#checks.x86_64-linux.fresh": { "/nix/store/hhh-fresh": 64 } }' store.json > s.json && mv s.json store.json
    rm -f calls/pushed
    GITHUB_REF=refs/pull/1/merge bash scripts-under-test/build-unless-proven.sh \
      .#checks.x86_64-linux.fresh .#checks.x86_64-linux.lonely >/dev/null 2>&1
    if [ "$(cat calls/pushed 2>/dev/null)" = /nix/store/hhh-fresh ]; then
      ok "a check that was built gets its proof pushed, and a proven one does not"
    else
      bad "build-unless-proven pushed: $(tr '\n' ' ' < calls/pushed 2>/dev/null)"
    fi

    [ "$fails" = 0 ] || { echo "$fails case(s) failed"; exit 1; }
    touch $out
  ''
