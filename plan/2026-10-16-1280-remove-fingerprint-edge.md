---
status: approved
issue: 1280
spec: spec/2026-10-16-1280-remove-fingerprint-edge.md
---

# Plan: Removing fingerprint authentication leaves edge's `/usr` exceptions

## Decisions carried from the approved spec

- One **edge carry commit**, not a change to main. Work in
  `/mnt/data/vmtest/wt-edge` on branch `edge-next`, reset to `origin/edge`
  (`46bac760` or newer). Stable has no `remove_resume_hook`, so the same patch
  on main would `--replace-fail` on nothing.
- `remove_resume_hook` is **deleted, body and all**, the way
  `remove_pam_config` already is, and its call becomes `:`. The body is what
  names `/usr`, so deleting the call alone does not take the command off the
  scan.
- **Nothing else in the script changes**: the identity check (and its
  existing `/run/current-system/sw/bin/id` rewrite at `default.nix` ~926), the
  package drop, removing `/etc/pam.d/omarchy-lock-fingerprint`, and deleting
  `/var/lib/fprint/<user>`.
- **No new check.** The `session` check's `/usr` scan
  (`tests/session.nix` ~1917-1937) is the guard once the command leaves
  `allowed`.
- Upstream facts this relies on (`quattro` `51bfd1d`, the edge pin):
  `remove_resume_hook() {` at line 46, its closing `}` at column zero on line
  57, the bare call `remove_resume_hook` on line 64, and no other occurrence of
  the name.

## Steps

1. **`pkgs/omarchy/default.nix`, the PAM block (~1372-1395 on edge).**
   - Add `omarchy-remove-security-fingerprint:remove_resume_hook \` to the
     `for pair in` list, so the build stops if the function moves or is
     renamed.
   - After the existing `sed -i '/^remove_pam_config() {$/,/^}$/d' …` line,
     add one for this file only:
     `sed -i '/^remove_resume_hook() {$/,/^}$/d' $pambin/omarchy-remove-security-fingerprint`
   - Extend the survived-the-delete `grep` alternation with
     `\|remove_resume_hook`.
   - In the existing `substituteInPlace $out/share/omarchy/bin/omarchy-remove-security-fingerprint`
     (~1447), add `--replace-fail 'remove_resume_hook' ':'`, with a one-line
     comment: the build declares the resume restart (#1288), so there is
     nothing to remove.

   Verify, on the package tier (§6: load below 12 and no p620 system build):
   `nix build .#omarchy --no-link --print-out-paths`, then on
   `$out/share/omarchy/bin/omarchy-remove-security-fingerprint`:
   - `grep -n '/usr/'` prints nothing;
   - `bash -n` passes;
   - `grep -q 'fingerprint_user=$(/run/current-system/sw/bin/id'` and
     `grep -q 'nothing to unpick'` both succeed, which shows the range delete
     did not eat the neighbours;
   - the line after `remove_lock_fingerprint_pam` is `:`.

   Traps: §5 — after any `.nix` edit, run `nix fmt` and read
   `git diff --stat`, because a hook may reformat with `nixpkgs-fmt`. A flake
   sees only tracked files, so `git add` before building.

2. **`tests/session.nix` (~1876-1878 on edge).** Delete the two comment lines
   (`# quattro (edge, #1278): removing a fingerprint edits` / `# /etc/pam.d/sudo
   in place, which NixOS generates (#1280).`) and the
   `"omarchy-remove-security-fingerprint",` entry from `allowed`.

   Verify: `nix eval --raw .#checks.x86_64-linux.session.drvPath` evaluates.
   The VM run is not local (§6); the edge pipeline's `verify` job runs it.

3. **`data/bin-ledger.nix` (~473-477 on edge).** Keep `class = "patch"` and
   `allow = "etc-write"`. Replace `reason` with:
   "Two functions go. remove_pam_config seds /etc/pam.d/sudo, a symlink into
   /etc/static/pam.d that `sed -i` detaches, as in omarchy-remove-security-fido2.
   quattro's remove_resume_hook deletes a /usr/lib sleep hook and an fprintd
   drop-in the build declares instead (#1288), so here it has nothing to
   remove. Dropping the packages, the omarchy-lock file and the user's saved
   prints stays."

   Verify: `flock /mnt/data/vmtest/codex-build.lock nix build .#checks.x86_64-linux.bin-ledger`.

## Tests

- **Red proof (§1), on the cheap tier.** The session scan is a shell loop;
  run the same loop by hand against the built tree:

  ```bash
  #!/usr/bin/env bash
  cd "$1/share/omarchy/bin"
  for f in *; do
    code=$(grep -v '^[[:space:]]*#' "$f" 2>/dev/null || true)
    [[ $code == *'/usr/'* ]] && basename "$f"
  done | grep -x omarchy-remove-security-fingerprint
  ```

  Built from the tree with step 1 reverted (`git stash` of
  `pkgs/omarchy/default.nix` only, then `git add -A` and build), it prints the
  name and exits 0. Built with step 1, it prints nothing and exits 1. Check the
  break landed with `git diff` before reading the result (§1). Restore with
  `git checkout HEAD -- <path>` or `git stash pop`, never `git checkout --`
  (§5). Put both outputs in the commit message or the #1280 comment.
- `checks.bin-ledger` passes.
- `nix fmt -- --ci`, `statix check .` and `deadnix --fail .` are clean.
- **Publish:** commit on `edge-next` with a full-sentence subject, push as a
  fast-forward to `edge-candidate`, and dispatch `omarchy-edge.yml` with
  `from_candidate=true`. `prepare`, `wait-idle`, `verify` (`options`,
  `session`, `coexist`, `plugin`) and `promote` must all be green, and `edge`
  must contain the commit.

## Close-out

- Correct the #1280 status comment: the PAM edit was already patched, and
  `/usr/bin/id` was already rewritten.
- Close #1280 once `edge` contains the carry, and check it closed.
- This branch (`fix/1280-remove-fingerprint-edge`, artifacts only) goes to
  main as a PR that links all three files and says the code is on `edge`.

## Rollback

Revert the carry commit on `edge-next`, push it as a fast-forward to
`edge-candidate`, and publish again. Edge only fast-forwards, so the revert
is a new commit, never a force-push (§11).
