---
status: draft
issue: 1248
spec: spec/2026-10-12-1248-hyprland-cache-key.md
---

# Plan: nixarchy trusts Hyprland's binary cache with the key Hyprland publishes

## Approved decisions

These are carried over from the spec and need no other file to act on.

- **The key is wrong.** It is
  `hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIITemDosxrE9/Kb+PfYvE=`
  and has been since the first commit. The published key is
  `hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc=`,
  the only key in the Cachix API's `publicSigningKeys`.
- **Nothing was built from source because of it.** nixarchy.cachix.org
  serves the shipped Hyprland under nixarchy's own signature. Machines
  downloaded it from us, so Hyprland depended on our eviction-prone 5 GB tier.
- **The six copies stay copies.** One check holds them equal.
- **The guard is one offline check, `checks.cache-keys`.** It does two
  things:
  - every `<cache>.cachix.org-1:` key in the code tree has exactly one
    distinct value per cache;
  - that value verifies the `Sig` of a committed narinfo fixture from the
    same cache.

  There is no nightly network check and no workflow edit (§4: `omarchy`'s
  generated step builds any new check).
- **Docs:** `docs/internals/flake.md:118`, the `setup-nix` comment, and a
  paragraph in `tests/AGENTS.md`. `build.yml` and `cache-allowlist.sh`
  are left alone.
- **The cache-budget undercount gets its own issue.** It is not changed
  here.
- **Mode A and coexistence are unchanged.** The module copy stays behind
  `binaryCaches`. The keys list merges, so there is no fixture to add.

**Prototype, already proven on 2026-10-12.** A Python/pynacl verifier of the
fingerprint `1;<StorePath>;<NarHash>;<NarSize>;<refs as /nix/store/… joined
by ",">` returned:

- **Hyprland's narinfo:** `ok` with the new key, and `BadSignatureError` with
  the old one;
- **nixarchy's narinfo:** `ok`.

## Steps

1. **The key, in six files.** Replace the old key string with the new one at
   `flake.nix:12`, `modules/nixos.nix:1062`,
   `.github/actions/setup-nix/action.yml:51`, `installer/cd.nix:819`,
   `installer/install.sh:51` and `installer/vm.nix:57`.
   → Verify: `grep -rn jIITemDosxrE9 . --exclude-dir={intent,spec,plan,.git}`
   prints nothing, and `grep -rc jIBMioiJM7ypFP8 …` finds 6.
   Traps: install.sh carries it in a space-separated string. Change only the
   key, not the quoting.

2. **Fixtures.** Create `tests/fixtures/cache-keys/hyprland.narinfo` and
   `tests/fixtures/cache-keys/nixarchy.narinfo`, each copied verbatim from
   `curl -s https://<cache>.cachix.org/irfl45bji5y4iba41l5yj05fy3di5hak.narinfo`.
   It is the same path in both caches, each with its own `Sig`.
   → Verify: each file has `StorePath`, `NarHash`, `NarSize`, `References` and
   a `Sig: <cache>.cachix.org-1:` line.
   Traps:
   - `git add` them before any flake build (§5).
   - If nixarchy has since evicted the path, take any narinfo it serves with a
     nixarchy `Sig`, and say which in the commit.

3. **The verifier, `tests/cache-keys.py`.** It is a separate file, so the
   check has no heredoc in a Nix string (§5, the nixfmt reindent trap).
   - **Arguments:** `<narinfo> <full key>`.
   - **Parse:** `key: value` lines, where `References` may be empty.
   - **Fingerprint:** build it as above, pick the `Sig` whose name matches
     the key's, and verify with `nacl.signing.VerifyKey`.
   - **Exit:** 0 on success. On failure, exit non-zero and print a message
     naming the narinfo and the key, plus "no Sig for <name>" when none
     matches.

   → Verify: run it by hand under
   `python3.withPackages (p: [ p.pynacl ])` with `-I` against both
   fixtures. The new key gives 0 and the old key gives non-zero.

4. **The check, `tests/cache-keys.nix`.** Shape it like
   `tests/grep-q-pipefail.nix`: `{ pkgs, ... }:`, then a
   `lib.fileset.toSource` with `root = ../.` over `../flake.nix`,
   `../modules`, `../installer`, `../pkgs`, `../tests` and `../.github`.
   It deliberately leaves out `intent/`, `spec/`, `plan/` and `docs/`, which
   quote the old key. The `runCommand "nixarchy-cache-keys"` uses
   `set -euo pipefail`, then:
   - **Collect.** Run
     `grep -rnoE '[a-z0-9-]+\.cachix\.org-1:[A-Za-z0-9+/]{43}='` over the
     source and keep `file:line:key`. Exit status 1 (no match) is a failure:
     "found no cachix keys, so nothing was checked". Exit status above 1 is a
     grep failure.
   - **Expect both caches.** If either `hyprland` or `nixarchy` has no key
     at all, fail.
   - **Disagree.** For each cache, more than one distinct key fails, and
     the error prints every `file:line:key` for that cache.
   - **Verify.** For each of the two caches, run the verifier against
     `${./fixtures/cache-keys}/<cache>.narinfo` with the single key. On
     failure, print "<cache>: the key in the tree does not verify a real
     <cache>.cachix.org signature".
   - On success, `touch $out`.

   The `fixtures/cache-keys` path is relative to `tests/`.
   → Verify: step 6.
   Traps:
   - **Under `set -e`, guard grep's 1-vs-2 exit statuses explicitly**, the
     way `grep-q-pipefail.nix` does with `|| rc=$?`.
   - **The `[a-z0-9-]+` prefix must include `nixarchy`, and a cache name
     must not swallow a URL.** The `-1:` makes the key the only match.

5. **Wire it into `flake.nix`.** Add `cache-keys = import ./tests/cache-keys.nix
   { pkgs = pkgsFor.${system}; };` after the `docs-lists` entry
   (~`flake.nix:2377-2382`), with a two-line comment above it: the Hyprland
   key was wrong from the first commit and nothing noticed, because our cache
   served the same paths (#1248).
   → Verify: `nix eval --raw .#checks.x86_64-linux.cache-keys.drvPath`.
   Traps: run `nix fmt` and read `git diff --stat` (§5, the hook reformat
   trap).

6. **§1 proof.** Commit a known-good baseline first, then build
   `checks.cache-keys` under `flock /mnt/data/vmtest/codex-build.lock`.
   - **(a)** Build it on the fixed tree. It must pass.
   - **(b)** Put the old key back in `flake.nix` only. Check `git diff` shows
     the break, `git add`, build. It must fail on "disagree", naming
     `flake.nix:12`. Restore with `git checkout HEAD -- flake.nix`.
   - **(c)** Put the old key back in all six files. Check `git diff`,
     `git add`, build. It must fail on hyprland's signature. Restore with
     `git checkout HEAD -- <the six>`.
   - **(d)** Rebuild. It must pass.

   Save the output of (b) and (c) for the PR.
   Traps: `git checkout HEAD --`, never `git checkout --`, because the index
   holds the break (§5). Then `git status` must be clean.

7. **Docs.**
   - **`docs/internals/flake.md:118`.** The cell becomes: **fetched** —
     `hyprland.cachix.org`, and `nixarchy.cachix.org` as a second source.
     Then add one sentence below the table: until #1248 the key for
     hyprwm's cache was wrong, so Hyprland came only from
     nixarchy.cachix.org, and `checks.cache-keys` now verifies it against a
     real signature.
   - **`.github/actions/setup-nix/action.yml:44-46`.** Replace "The store
     path nixarchy uses is byte-identical to the one hyprwm publish --
     verified, not assumed -- so with this the compositor is a download"
     with the corrected claim. The path is byte-identical. The download came
     from nixarchy.cachix.org until #1248, because the key for hyprwm's
     cache was wrong. `checks.cache-keys` holds it now.
   - **`tests/AGENTS.md`.** Add a section after "A list check must look
     where the item lives…" (line 1284), before "The cheap ones…": **A trust
     key is checked by a signature, not by comparing it with itself.** The
     paragraph says:
     - a substituter key that is wrong stays silent when another cache
       serves the same paths;
     - `cache-keys` verifies a committed narinfo, which does not expire;
     - a key change means refreshing the fixture.

   → Verify: `bash .github/scripts/readme-counts.sh` still passes, if it
   reads either file.
   Traps: insert the AGENTS.md section between existing ones. Do not
   renumber anything; tests/AGENTS.md sections are not numbered.

8. **Real-world proof for the PR, run once.** Run
   `nix store verify --no-contents --store https://hyprland.cachix.org
   --option trusted-public-keys '<key>'
   /nix/store/irfl45bji5y4iba41l5yj05fy3di5hak-hyprland-0.56.0+date=2026-10-03_9dc5398`
   with the new key (passes) and the old key (`untrusted`). Also run
   `nix eval --json .#nixosConfigurations.vm.config.nix.settings.trusted-public-keys`
   and check the output shows the new key.

9. **Commit, PR, follow-ups** (the session model).
   - **Commit.** One full-sentence subject, with `Closes #1248` once.
   - **Before the PR.** Check whether `main` has moved, and read the agent
     bus.
   - **The PR body:**
     - the links to the intent, spec and plan;
     - the outputs of steps 6 and 8;
     - that the coder did steps 1–7;
     - a note that `setup-nix` is CI plumbing and needs a human merge (§11);
     - the out-of-repo copies to fix: `nixos_config` (`flake.nix`,
       `modules/services/nixarchy-runner.nix`) and `nixarchy-hyprflip`.
   - **The follow-up issue.** File "cache-budget.sh may undercount:
     nixarchy.cachix.org stores paths hyprland.cachix.org serves", with
     milestone "Keeping the lights on" and labels `bug` and `ci`.

## Tests

| command | expected |
|---|---|
| `nix build .#checks.x86_64-linux.cache-keys -L` | passes on the fix; fails on (b) and (c) |
| `nix fmt -- --ci` | clean |
| `nix run nixpkgs#statix -- check .` and `nix run nixpkgs#deadnix -- --fail .` | clean |
| `nix eval .#checks.x86_64-linux.cache-keys.drvPath` | evaluates |

CI then runs `cache-keys` inside `omarchy`'s generated step. The run log's
list will confirm it.

## Rollback

Revert the squash commit. The old key is inert: it verifies nothing, and
nixarchy.cachix.org keeps serving Hyprland. Rolling back loses nothing but
the second source.
