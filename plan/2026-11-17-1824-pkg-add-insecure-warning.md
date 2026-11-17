---
status: approved
issue: 1824
spec: spec/2026-11-17-1824-pkg-add-insecure-warning.md
coders:
  1: codex  # small tricky logic: Nix-in-bash-in-Nix quoting, tryEval guards
  2: codex  # the cross-check test against the fixture nixpkgs
  # step 3 is lead-only: break proofs, fmt, statix, deadnix, builds, commits
reviewers:
  - codex  # reads the diff natively
  - agy    # independent model; given named files only (a print timeout hit on a broad review)
---

# Plan: `nixarchy-pkg-add` warns after adding an insecure package (#1824)

Self-contained. Spec: `spec/2026-11-17-1824-pkg-add-insecure-warning.md`
(approved). Worktree `/mnt/data/vmtest/wt-1825`, branch
`fix/1825-1824-home-plan-insecure`. Anchors by name in `modules/apps.nix`
(`nixarchy-pkg-add`; the `probe` expression passed to `nix-instantiate --expr`,
and the flags paragraph that sets `flags=" [unfree ..."` and
`[broken in nixpkgs ...]`).

**Handoff rules for every step.** The coder must not commit, stage, deploy,
restart, build, format or print the environment, and edits only the files the
step names. The lead runs `nix fmt`, reads `git diff --stat`, statix, deadnix,
`git add`s, runs the check under `flock /mnt/data/vmtest/codex-build.lock`, and
commits one step per commit (full-sentence subject, no conventional prefix).

## Approved decisions (from the spec)

1. Same meaning as the index (`row` in `modules/pkg-index.nix`): insecure =
   `meta.insecure == true` OR `meta.knownVulnerabilities` a non-empty list; each
   predicate under its own `tryEval` falling back to false; whole-`meta` throw
   keeps today's "no match" (unchanged).
2. In the probe `let`, beside `ls` (not in `v = { }`):
   `try = x: d: let r = builtins.tryEval x; in if r.success then r.value else d;`
   and `m = try (q.meta or { }) { };`. In `v`, beside `broken`:
   `insecure = builtins.isAttrs m && (try ((m.insecure or false) == true) false || try (let kv = m.knownVulnerabilities or null; in builtins.isList kv && kv != [ ]) false);`.
   Only a boolean enters `v`. The text sits in a bash double-quoted string in a
   Nix `''` string: no `$`, backtick, `''` or `${` may appear in it.
3. Flags paragraph, after the broken test:
   `if [ "$(jq -r .insecure <<<"$info")" = true ]; then flags="$flags [insecure in nixpkgs -- the rebuild will refuse it unless you permit it]"; fi`.
   Order: unfree, broken, insecure. The package is still added. The
   other-channel branch is untouched.

## Steps

1. `modules/apps.nix`: decisions 2 and 3 only. Verify: `nix fmt`, then
   `flock /mnt/data/vmtest/codex-build.lock nix build
   .#checks.x86_64-linux.app-selection .#checks.x86_64-linux.home-selection
   --no-link` (they run the probe on real nixpkgs; a quoting slip breaks every
   add). Traps: the `--expr` is inside `"..."` inside `''...''`; `\"` is the
   in-expression double quote convention already used there; `it ''${` is not
   needed (no `${`); the jq line is plain bash in the `''` string (`$(` and
   `$info` need no escaping).
2. `tests/pkg-index.nix`: the verification of the spec, as follows. Add a
   section to the check script (the non-golden branch, after the existing
   flags/preview assertions), run under `set -eo pipefail`:
   - make an executable writable copy with `install -m755
     ${testLib.vmPackage "nixarchy-pkg-add"}/bin/nixarchy-pkg-add pkg-add-copy`
     (store files are 0555; `cp` keeps that), then
     `sed -i "s|^\( *\)nixpkgs=.*|\1nixpkgs=${fixture}|;s|^\( *\)allowunfree=.*|\1allowunfree=true|"`
     and `grep -qF "nixpkgs=${fixture}"` and `grep -qx 'allowunfree=true'` to prove
     both landed (fail otherwise). `allowunfree=true` makes `fixAll` print the
     `[unfree -- fine here ...]` notice whatever the VM config baked, with no
     unfree-grant prompt.
     Note `''${` escaping in the Nix string for any bash `${}`.
   - private `HOME`, `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, all `mkdir -p`ed
     (`$XDG_CONFIG_HOME/nixarchy` too; `HOME` is `/homeless-shelter` otherwise);
     `NIX_STATE_DIR` and
     `NIX_LOG_DIR` are already set by the check. `jq` and `gnused` are already
     in `nativeBuildInputs`; add anything missing (`flock` is `util-linux`, add
     it) to `nativeBuildInputs`, since the script's `runtimeInputs` do not reach
     the copy's PATH unless the copy keeps its own `PATH=` line (it does: a
     `writeShellApplication` exports it).
   - per attribute in `walk.json` (`jq -r '.[].attr'`) except `fixCurated`:
     rewrite `$XDG_CONFIG_HOME/nixarchy/apps.nix` to the empty marker block
     (`{ pkgs, ... }:` / `{` / `  environment.systemPackages = with pkgs; [  #@pkgs-begin` /
     `  ];  #@pkgs-end` / `}`; build it with `printf '%s\n'`, not a heredoc,
     CLAUDE.md s5), run the copy as `rc=0; "$copy" "$attr" >"out.$attr" 2>&1 || rc=$?`.
   - case 1: attrs whose output row contains the whole notice
     `[insecure in nixpkgs -- the rebuild will refuse it unless you permit it]` to
     `got.txt`; index insecure set minus `fixCurated` from `walk.json` to
     `want.txt`; sort both; assert `want.txt` is non-empty; `diff` them.
   - case 2: `fixAll` row has `[unfree`, `[broken`, `[insecure` in this order:
     `u=index(row,"[unfree"); b=index(row,"[broken"); i=index(row,"[insecure")`
     and require `u > 0 && u < b && b < i` (`index` returns 0 when absent, so a
     bare `<` chain would pass with the notice missing); `fixClean` output ends
     in `fixClean -- clean package` (the probe reads `name`, which the fixture
     sets without the version; CORRECTS spec case 2, which said `fixClean-1.0`)
     and has no `[`.
   - case 3: `fixThrowVuln fixThrowElem fixThrowInsecureList fixInsecureThrowVuln`
     have rc 0 and an `added` row; `fixThrowMeta` has rc != 0 and `no match`.
   - failures go through the file's existing `fail` helper (they accumulate);
     put the whole section BEFORE the final `[ "$fails" -eq 0 ] || exit 1` /
     `touch "$out"` lines, or a `fail` there is a silent pass; write `diff -u
     want.txt got.txt || fail '...'` so `set -e` does not skip accumulation.
   Verify: `nix build .#checks.x86_64-linux.pkg-index --no-link` green. Traps:
   the check's `''` string escaping; process substitution swallows a producer's
   failure (use files); a second add of the same name reports "already in"
   (reset the file per run); the golden branch (`goldenOnly`) must stay
   untouched, so add the section only inside the non-golden `''` block.
3. Lead only: break proofs (spec Verification 4: (i) delete the flags line,
   (ii) drop the `try` around `(m.insecure or false) == true` (keep the
   `knownVulnerabilities` disjunct), (iii) drop the `try` around the
   `knownVulnerabilities` read), each shown landed by `git diff`, restored with
   `git checkout HEAD -- <path>` from a committed baseline; then
   `app-selection home-selection pkg-index pkg-new`, statix, deadnix,
   `nix fmt`; then every target `.github/scripts/generated-checks.sh generated`
   prints, in one `nix build --keep-going --max-jobs 2 --no-link`, under the
   flock, and the four options shards
   (`.#checks.x86_64-linux.options-{system,home,microvm,files}`) once the gates
   in CLAUDE.md s6 allow (no busy self-hosted runner, load under 12).

## Tests

`pkg-index`, `app-selection`, `home-selection`, `pkg-new` green; each break
proof turns its named case red.

## Rollback

`git revert` the two step commits (test depends on code, so revert the test
first).
