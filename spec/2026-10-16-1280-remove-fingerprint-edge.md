---
status: approved
issue: 1280
intent: intent/2026-10-16-1280-remove-fingerprint-edge.md
---

# Spec: Removing fingerprint authentication leaves edge's `/usr` exceptions

## Design

One edge carry commit on `edge-next` (worktree `wt-edge`), pushed to
`edge-candidate` as a fast-forward and published by `omarchy-edge.yml`, the
same route as the language and apply-lock carries.

1. **`pkgs/omarchy/default.nix`, the PAM block (edge ~1372-1395).**
   `remove_resume_hook` goes the way `remove_pam_config` already does, in the
   same block:
   - add `omarchy-remove-security-fingerprint:remove_resume_hook` to the
     `for pair in` loop, so the build stops if `quattro` renames or moves it;
   - add `-e '/^remove_resume_hook() {$/,/^}$/d'` for that one file. The
     function body is what names `/usr`, so the body has to go, not only the
     call;
   - extend the survived-the-delete `grep` to `remove_resume_hook`;
   - `substituteInPlace … --replace-fail 'remove_resume_hook' ':'` for the
     bare call that remains (line 64 upstream). With the body deleted, the
     call is the only match.
   Nothing else in the script changes: the identity check, the existing
   `/run/current-system/sw/bin/id` rewrite (~926), dropping the packages,
   removing `/etc/pam.d/omarchy-lock-fingerprint`, and deleting
   `/var/lib/fprint/<user>`.
2. **`tests/session.nix` (edge ~1876-1878).** Remove
   `"omarchy-remove-security-fingerprint"` and its two-line comment from
   `allowed`. The comment is wrong anyway (it says the command edits
   `/etc/pam.d/sudo`).
3. **`data/bin-ledger.nix` (edge ~473-477).** Keep `class = "patch"` and
   `allow = "etc-write"`; the command still removes a file under `/etc/pam.d`.
   Rewrite `reason` to say both deletions: the PAM edit, and the resume-hook
   cleanup that has nothing to clean because the build declares it (#1288).

**The guard is the `session` check's `/usr` scan** (edge ~1917-1937). It
greps every shipped command's non-comment lines for `/usr/` and fails on any
not in `allowed`. Once the command leaves `allowed`, a `quattro` change that
brings a `/usr` path back into it fails `session`. No new check: a second
one that greps the same file for the same string would be the property
provided twice (§1).

## Alternatives rejected

- **Replace only the call with `:`.** The function body would still be
  shipped code that names `/usr`, so the scan would still list it.
- **Rewrite the paths to NixOS equivalents.** There are none: the resume
  restart is a declared unit (#1288), and there is no drop-in to remove.
- **Keep the exception and fix only its comment.** The intent's outcome is
  that the command leaves the list.
- **Do it on main.** Stable's script has no `remove_resume_hook`, so a main
  patch would `--replace-fail` on nothing and break the stable build (#1278:
  no version conditionals on main).

## Risks

- **A `quattro` rewrite of the function** (renamed, or a `}` not at column
  zero) stops the edge build at the `for pair` guard or the survived-the-delete
  grep. That is the intended failure: edge stops moving rather than shipping a
  half-patched script.
- **The range delete eats too much** if the function's closing `}` were
  indented. The survived-the-delete grep does not catch that; the session
  scan and the language-edge-style build do not either. Mitigation: the plan's
  step checks the built script with `bash -n` and greps that the identity
  block and `remove_pam_config`'s replacement message are still present.
- Only edge machines are affected, and the change removes a no-op.

## Verification

- **Build:** `nix build .#omarchy` on `edge-next`. In the built
  `omarchy-remove-security-fingerprint`: no `/usr/`, `bash -n` passes,
  `fingerprint_user=` and the PAM message are still there, and the call site
  reads `:`.
- **Ledger:** `checks.bin-ledger` on `edge-next`.
- **Red proof (§1), cheap:** with step 1 reverted and step 2 kept, the
  session scan's own shell loop, run against the built tree in a
  `runCommand` or by hand, lists `omarchy-remove-security-fingerprint`; with
  step 1 restored it does not. The VM `session` run itself is left to the
  edge pipeline's `verify` job (§6: VM checks only when CI is idle).
- **Publish:** `omarchy-edge.yml` `prepare` → `verify` (`options`,
  `session`, `coexist`, `plugin`) → `promote`, all green.
- **Close-out:** #1280's status comment corrected, and #1280 closed once
  `edge` contains the carry.
