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
#   cachix-push.sh       closures from main, and from this repository's dated
#                        nixpkgs bump PRs minus commit-specific paths.
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
    # #788: cold box checks must be able to fetch the pinned image from our
    # cache, not only Docker Hub. Exercise the real publication allowlist.
    allowed=$(bash "$scripts/cache-allowlist.sh" system)
    if [ "$(grep -cxF '.#box-test-image' <<<"$allowed" || true)" -ne 1 ]; then
      echo 'box-test-image is missing or duplicated in the system cache allowlist' >&2
      exit 1
    fi

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
      ".#flaky":  { "/nix/store/hhh-flaky": $((7 * MiB)) },
      ".#omarchy": { "/nix/store/ooo-omarchy": $((1 * MiB)) },
      ".#bumpy":  { "/nix/store/iii-refsrc": $((1 * MiB)), "/nix/store/jjj-keep": $((1 * MiB)) },
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
      "build --no-link")
        if [ "\$3" = --json ]; then
          # The batch: one result per installable, in argument order.
          [ -z "\$STUB_BATCH_FAILS" ] || exit 1
          shift 3
          for a in "\$@"; do closure_of "\$a" | grep -q . || exit 1; done
          for a in "\$@"; do closure_of "\$a" | jq -c '{ outputs: { out: keys_unsorted[0] } }'; done | jq -cs .
        else closure_of "\$3" | grep -q .; fi ;;
      "build --keep-going") exit 0 ;;
      "flake metadata")
        [ -z "\$STUB_META_FAILS" ] || exit 1
        echo '{"path":"/nix/store/src-flake"}' ;;
      "eval --raw")
        if [ "\$3" = .#omarchy.outPath ]; then
          [ -z "\$STUB_EVAL_FAILS" ] || exit 1
          echo /nix/store/ooo-omarchy
        else jq -r --arg k "\$3" '.[\$k] | keys_unsorted[0]' "\$store"; fi ;;
      "path-info -r")
        case "\$3 \$4" in *.#flaky*|*/nix/store/hhh-flaky*) exit 1 ;; esac
        if [ "\$3" = --json ]; then closure_of "\$4" | jq -c 'map_values({ narSize: . })'
        else closure_of "\$3" | jq -r 'keys[]'; fi ;;
      path-info*)
        # The tree is not in the local store when STUB_TREE_ABSENT is set.
        [ -z "\$STUB_TREE_ABSENT" ] || [ "\$2" != /nix/store/ooo-omarchy ] || exit 1
        closure_of "\$2" | grep -q . ;;
      *) echo "stub nix: unexpected \$*" >&2; exit 9 ;;
    esac
    EOF
    # nix-store --query --referrers-closure: records its roots, and names the
    # path that references the flake source (iii-refsrc) ONLY when the source is
    # among them, as the real command would.
    cat > bin/nix-store <<EOF
    #!${pkgs.bash}/bin/bash
    [ "\$1 \$2" = "--query --referrers-closure" ] || { echo "stub nix-store: unexpected \$*" >&2; exit 9; }
    [ -z "\$STUB_NIXSTORE_FAILS" ] || exit 1
    shift 2
    printf '%s\n' "\$@" >> $work/calls/nixstore-roots
    printf '%s\n' "\$@"
    for a in "\$@"; do [ "\$a" != /nix/store/src-flake ] || echo /nix/store/iii-refsrc; done
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

    # (a) Under budget: 10 + 20 + 5 + 400 (shared once) = 435 MiB of 2560.
    if got=$(bash $budget .#small .#other .#twin 2>&1); then
      ok "entries under the budget pass"
    else
      bad "entries under the budget failed:"; printf '%s\n' "$got"
    fi

    # (a2) The batch and the per-entry fallback must report the same thing, and
    # the fallback must still name the entry that does not build.
    want=$(bash $budget .#small .#other .#twin 2>&1)
    got=$(STUB_BATCH_FAILS=1 bash $budget .#small .#other .#twin 2>&1)
    if [ "$want" = "$got" ] && grep -q ', 435 MiB of' <<<"$got"; then
      ok "the per-entry fallback reports what the batch does"
    else
      bad "batch and fallback disagree:"; printf '%s\n---\n%s\n' "$want" "$got"
    fi
    if got=$(bash $budget .#small .#absent 2>&1); then
      bad "an entry that does not build passed the budget"
    elif grep -q '::error::.#absent does not build' <<<"$got"; then
      ok "a failed batch falls back and names the entry that does not build"
    else
      bad "a failed batch did not name the entry:"; printf '%s\n' "$got"
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
      bad "3 GB of allowlist passed a 2.5 GB budget"
    elif grep -q '::error::the allowlist costs 3010 MiB' <<<"$got" && grep -q 'from .#huge' <<<"$got"; then
      ok "over budget fails, naming the entry that grew"
    else
      bad "over budget failed without naming the entry:"; printf '%s\n' "$got"
    fi

    # (b2) An entry whose closure cannot be read must fail the budget, not
    # pass as if it cost nothing. `build --no-link` still succeeds for it.
    if got=$(bash $budget .#small .#flaky 2>&1); then
      bad "an entry whose closure could not be read passed the budget"
    elif grep -q '\.#flaky' <<<"$got"; then
      ok "an unreadable closure fails the budget, naming the entry"
    else
      bad "an unreadable closure failed without naming the entry:"; printf '%s\n' "$got"
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

    # (g2) A nixpkgs bump PR from THIS repository pushes the closure minus what
    # references the source; a fork's branch of the same name, and any other PR,
    # push nothing.
    printf '%s\n' '{"pull_request":{"head":{"repo":{"full_name":"o/r"}}}}' > own.json
    printf '%s\n' '{"pull_request":{"head":{"repo":{"full_name":"fork/r"}}}}' > fork.json
    pr() { # head-ref event-file; STUB_* set by the caller reach the stubs
      GITHUB_REF=refs/pull/1/merge GITHUB_EVENT_NAME=pull_request GITHUB_REPOSITORY=o/r \
        GITHUB_HEAD_REF=$1 GITHUB_EVENT_PATH=$2 bash $push .#bumpy >pr.log 2>&1
    }
    rm -f calls/pushed calls/nixstore-roots
    pr update/nixpkgs-2026-10-26 own.json
    if [ "$(cat calls/pushed 2>/dev/null)" = /nix/store/jjj-keep ]; then
      ok "a bump PR pushes the closure minus what references the source"
    else
      bad "a bump PR pushed: $(tr '\n' ' ' < calls/pushed 2>/dev/null)"
    fi
    rm -f calls/pushed
    pr update/nixpkgs-2026-10-26 fork.json
    if [ ! -s calls/pushed ]; then
      ok "a fork's bump-named branch pushes nothing"
    else
      bad "a fork's branch pushed: $(tr '\n' ' ' < calls/pushed)"
    fi
    rm -f calls/pushed
    pr feature/other own.json
    if [ ! -s calls/pushed ]; then
      ok "an ordinary PR pushes nothing"
    else
      bad "an ordinary PR pushed: $(tr '\n' ' ' < calls/pushed)"
    fi

    # An undated branch (update/nixpkgs-blocked is where people push) is no bump.
    rm -f calls/pushed
    pr update/nixpkgs-blocked own.json
    if [ ! -s calls/pushed ]; then
      ok "an undated update/nixpkgs-* branch pushes nothing"
    else
      bad "an undated branch pushed: $(tr '\n' ' ' < calls/pushed)"
    fi

    # The tree is a root when it is in the local store ...
    if grep -qx /nix/store/ooo-omarchy calls/nixstore-roots && grep -qx /nix/store/src-flake calls/nixstore-roots; then
      ok "the source and the omarchy tree are both referrer roots"
    else
      bad "referrer roots were: $(tr '\n' ' ' < calls/nixstore-roots)"
    fi
    # ... and dropped, with the push going ahead, when it is not.
    rm -f calls/pushed calls/nixstore-roots
    STUB_TREE_ABSENT=1 pr update/nixpkgs-2026-10-26 own.json
    if [ "$(cat calls/pushed 2>/dev/null)" = /nix/store/jjj-keep ] &&
      ! grep -q ooo-omarchy calls/nixstore-roots && grep -qx /nix/store/src-flake calls/nixstore-roots; then
      ok "a tree that is not in the local store is dropped from the roots, and the push proceeds"
    else
      bad "tree-absent: pushed $(tr '\n' ' ' < calls/pushed 2>/dev/null), roots $(tr '\n' ' ' < calls/nixstore-roots 2>/dev/null)"
    fi

    # Every fail-safe pushes NOTHING: not knowing what is commit-specific must
    # never read as "nothing is".
    for failure in STUB_META_FAILS STUB_EVAL_FAILS STUB_NIXSTORE_FAILS; do
      rm -f calls/pushed
      env "$failure=1" bash -c "$(declare -f pr); push=$push; pr update/nixpkgs-2026-10-26 own.json" || true
      if [ ! -s calls/pushed ] && grep -q 'pushes nothing without the exclusion set' pr.log; then
        ok "$failure: a bump pushes nothing"
      else
        bad "$failure: pushed $(tr '\n' ' ' < calls/pushed 2>/dev/null); log: $(cat pr.log)"
      fi
    done
    for ev in missing.json empty.json; do
      : > empty.json
      rm -f calls/pushed
      pr update/nixpkgs-2026-10-26 $ev || true
      if [ ! -s calls/pushed ]; then
        ok "an unreadable event file ($ev) pushes nothing"
      else
        bad "event file $ev: pushed $(tr '\n' ' ' < calls/pushed)"
      fi
    done

    # (g3) A closure that cannot be read on main is an error and pushes nothing
    # for that entry -- not an empty list pushed as success.
    rm -f calls/pushed
    rc=0
    GITHUB_REF=refs/heads/main bash $push .#flaky >pr.log 2>&1 || rc=$?
    if [ $rc -ne 0 ] && [ ! -s calls/pushed ] && grep -q 'could not read the closure of .#flaky' pr.log; then
      ok "main: an unreadable closure is an error and pushes nothing"
    else
      bad "main with an unreadable closure: rc=$rc, pushed $(tr '\n' ' ' < calls/pushed 2>/dev/null)"
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
