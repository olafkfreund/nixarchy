{ pkgs, omarchy }:
# #963: omarchy-shell matched the running instance by CONFIG PATH. On Arch that
# is /usr/share/omarchy -- stable, so the match is correct. Here it is a store
# path that changes on every rebuild, so after a redeploy the caller holds the
# new one and the running shell registered under the old one. Every IPC call
# misses, and a plugin keybind silently does nothing.
#
# A stub `qs` on PATH, which works here and did NOT in tests/apply-confirm.nix:
# nixarchy-apply is a writeShellApplication with a strict PATH built from
# runtimeInputs, so the real binary always won. omarchy-shell is upstream's and
# unwrapped, so PATH is the whole mechanism.
#
# `res`, `out_*` -- never a bare `out`: $out is nix's output path and is in
# scope here. tests/apply-confirm.nix hit this first; this file hit it again
# four hours later, which is why the note there was not enough on its own.
# Every assertion passed and the derivation then failed to produce its output,
# with nothing in the log saying why.
#
# The stub records its own argv, because the assertion that matters is WHICH
# SELECTOR the script called with -- `-p` or `-i <id>`. "It printed something"
# is satisfied by any message and would pass with the fallback deleted.
pkgs.runCommand "nixarchy-shell-ipc-resolve"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
    ];
  }
  ''
    shell=${omarchy}/share/omarchy/bin/omarchy-shell
    [ -x "$shell" ] || { echo "omarchy-shell is not where the package builds it" >&2; exit 1; }

    export OMARCHY_PATH=$PWD/tree
    mkdir -p tree/shell stub
    : > tree/shell/shell.qml
    export PATH=$PWD/stub:$PATH
    export OMARCHY_SHELL_IPC_TIMEOUT=2s

    # The stub. QS_PROBE decides whether the caller's own path still has an
    # instance; QS_LISTING is what `qs list --all` prints.
    #
    # printf, not a heredoc: a heredoc body inside an indented Nix string has
    # to start at column zero, and nixfmt strips the block's common indent --
    # CLAUDE.md section 5. The first version of this file used one, the shebang
    # came out mangled, `qs` was never found, and the script reported "not
    # running" for every case.
    #
    # And the shebang is the store path, not /usr/bin/env: the build sandbox
    # has no /usr/bin/env, which AGENTS.md section 4 already records against
    # tests/proof-push.nix. env gives "bad interpreter", the stub never runs,
    # and every case reports "not running" -- the same symptom as the heredoc
    # bug, from a different cause.
    printf '%s\n' \
      '#!${pkgs.bash}/bin/bash' \
      'printf "%s\\n" "$*" >> "$QS_ARGV"' \
      'if [ "$1" = list ]; then printf "%s" "$QS_LISTING"; exit 0; fi' \
      'case "$*" in' \
      '  *__nixarchy_probe*) exit "''${QS_PROBE:-1}" ;;' \
      'esac' \
      'echo ok' \
      'exit "''${QS_CALL_RC:-0}"' > stub/qs
    chmod +x stub/qs

    listing_one=$(printf '%s\n' "Instance aaa111:" "  Config path: /nix/store/old-tree/shell/shell.qml")
    listing_two=$(printf '%s\n' "Instance aaa111:" "  Config path: /nix/store/old-tree/shell/shell.qml" \
                                "Instance bbb222:" "  Config path: /nix/store/other-tree/shell/shell.qml")

    run() { # run <name> <probe-exit> <listing>
      export QS_ARGV=$PWD/argv.$1 QS_PROBE=$2 QS_LISTING=$3
      : > "$QS_ARGV"
      res=$(bash "$shell" shell toggle some.plugin '{}' 2>&1 || true)
      echo "=== $1"; cat "$QS_ARGV"; printf '%s\n' "$res"
    }
    fail() { echo "FAIL: $1" >&2; exit 1; }

    # 1. The caller's path still has an instance: unchanged, called with -p.
    run keeps 0 "$listing_one"
    grep -q -- '-p .*tree/shell' argv.keeps || fail "the ordinary path did not call with -p"
    grep -q -- '-i ' argv.keeps && fail "the ordinary path fell back to an instance id"

    # 2. The caller's path is stale and one instance is running: -i that one.
    run falls 1 "$listing_one"
    grep -q -- '-i aaa111' argv.falls || fail "a stale path did not fall back to the running instance"

    # 3. Two instances: refuse, and name them. Guessing sends a keybind to the
    #    wrong screen.
    run two 1 "$listing_two"
    grep -qi "more than one" <<<"$(cat argv.two; true)" >/dev/null 2>&1 || true
    out_two=$(QS_ARGV=$PWD/argv.two2 QS_PROBE=1 QS_LISTING="$listing_two" bash "$shell" shell toggle x '{}' 2>&1 || true)
    grep -qi "more than one" <<<"$out_two" || fail "two instances were not refused"
    grep -q "aaa111" <<<"$out_two" || fail "the refusal did not name the instances"

    # 4. No instance at all: says the shell is not running.
    # QS_CALL_RC=1: with no instance anywhere, the real call fails too. Without
    # it the stub answers "ok" and the script cannot distinguish "no shell" from
    # "a shell that replied" -- the fixture, not the script, would be lying.
    out_none=$(QS_ARGV=$PWD/argv.none QS_PROBE=1 QS_LISTING="" QS_CALL_RC=1 bash "$shell" shell toggle x '{}' 2>&1 || true)
    grep -qi "not running\|not responding" <<<"$out_none" || fail "no instance did not say the shell is not running"

    # 5. Output qs never produced: REFUSE, do not report "no instance". Falling
    #    through there would restore the silent failure this patch removes,
    #    inside the fix for it.
    out_bad=$(QS_ARGV=$PWD/argv.bad QS_PROBE=1 QS_LISTING="something else entirely" bash "$shell" shell toggle x '{}' 2>&1 || true)
    grep -qi "cannot read qs list" <<<"$out_bad" || fail "an unreadable qs listing was not refused"

    mkdir -p $out
    echo "shell ipc resolve: 5 cases, all asserted"
  ''
