---
status: draft
issue: 1015
spec: spec/2026-09-26-1015-remote-desktop-onboarding.md
---

# Plan: Turn remote desktop on across a fleet, from the menu

Self-contained. Everything needed to implement this is below; the spec and
intent do not need opening.

## The approved decisions, carried over

- **Per-host passwords.** One sops secret per machine, as today. A shared
  fleet secret was rejected: one compromised machine would be every machine's
  desktop.
- **The menu is not QML.** It is `omarchy-menu.jsonc`, rows of
  `{icon, label, aliases, action, when}` that this repo already extends from
  `pkgs/omarchy/default.nix` (`askMenuRows`, line 142). A row's `action` is a
  shell command run in a floating terminal. No Quickshell panel, no bar widget.
- **The wizard stops at files we do not own.** It runs every mechanical step
  and *prints* the two lines destined for `hosts/<host>/configuration.nix`.
  Editing a user's `configuration.nix` by pattern-matching is the same hazard
  as splicing `.sops.yaml`.
- **`.sops.yaml` is written structurally, never by regex.** `yq-go` appends to
  `.keys` and `.creation_rules`. Enrolled hosts get their recipient written
  inline rather than as a YAML anchor: anchors round-trip worst, and a policy
  file sops cannot parse is a machine whose secrets will not decrypt.
- **`modules/services/hypr-rdp.nix` is not touched.** Neither the evaluation
  assertion nor the `ExecStartPre` guard moves. The daemon fails open and those
  two refusals are the only thing between an unset secret and an open desktop.

## Scope change since the spec was approved

**`connect` is out**, moved to **#1016** with the client choice and the new
"drivable by ai-mirror" requirement. So `freerdp`, `data/apps.nix` and the
`setup.remote.connect` row are **not** in this plan. What ships here is the
fleet onboarding: enrollment and turning incoming connections on.

The `setup.remote` menu parent is created here with one child. #1016 adds the
second.

## Steps

1. `pkgs/secret.nix`: add the `enroll` verb to the dispatcher (the `case` at
   line 687) and to the usage block (line 227) → verify by
   `nixarchy-secret --help` listing it and `nixarchy-secret enroll` not saying
   "unknown subcommand"

2. `pkgs/secret.nix`: add `yq-go` to the package's inputs and `runtimeInputs`
   → verify by `nix build .#nixarchy-secret` and `yq --version` from inside the
   built wrapper. An undeclared command is a runtime failure no build catches

3. `pkgs/secret.nix`: implement `enroll` — derive this host's recipient with
   `ssh-to-age -i "$HOST_KEY.pub"` exactly as `ensure_policy` already does;
   refuse with the existing sshd message when there is no host key; no-op with
   a message when the policy already has a rule for `hosts/$HOST/secrets.yaml`;
   otherwise `yq -i` the recipient into `.keys` and a creation rule into
   `.creation_rules` → verify by step 6's check

4. `pkgs/secret.nix`: change `ensure_policy`'s third branch to name `enroll`
   in its refusal instead of only printing YAML. It keeps refusing; it stops
   being a dead end → verify by running `nixarchy-secret new` on a host absent
   from a fixture policy and reading the message

5. `pkgs/omarchy/nix-bin/nixarchy-remote`: new `gum` wizard, `serve` verb only.
   Reports four states and offers the next unmet one: sshd on, secret present,
   service enabled, unit running. Runs `nixarchy-secret enroll` and
   `nixarchy-secret new hypr-rdp-password`. Prints the two `configuration.nix`
   lines with the full path. Prints nothing from the rendered config, ever →
   verify by running it on this machine and reading each branch

6. `tests/secret-enroll.nix`: new check. Fixture `.sops.yaml` carrying host A,
   a value encrypted to A, then `enroll` as host B and `sops updatekeys`;
   assert **both** identities decrypt. Also asserts idempotence and the
   no-host-key refusal. Write the fixture with `printf '%s\n' …`, **not** a
   heredoc — a heredoc body inside an indented Nix string lowers the block's
   common indent and `nix fmt` then rewrites the whole file → verify by
   step 10

7. `flake.nix`: add `checks.secret-enroll`. **Do not wire the workflow.**
   Naming it in `build.yml` is a CI-gate change and needs a human, so raise it
   in the PR instead → verify by `nix build .#checks.x86_64-linux.secret-enroll`
   locally and by saying so in the PR

8. `pkgs/omarchy/default.nix`: a `remoteMenuRows` fragment beside
   `askMenuRows`, via `builtins.toFile` for the same reason (JSON containing
   shell, one level of escaping), and its insertion into the generated menu.
   Two rows: `setup.remote` (parent) and `setup.remote.serve` →
   `omarchy-launch-floating-terminal-with-presentation nixarchy-remote serve`
   → verify by the build-time menu parse, which already exists

9. `data/bin-ledger.nix`: a row for `nixarchy-remote`, class `new` → verify by
   `.github/scripts/check-bin-ledger.py`, which fails both ways — a file with
   no row is unclassified, a stale row no longer matches

10. `nix fmt` and read `git diff --stat` before committing. A managed editor
    hook on this machine runs `nixpkgs-fmt` after every `.nix` edit and this
    repo uses `nixfmt`; the tell is `nix fmt -- --ci` failing once then passing
    → verify the diff is the size of the change, not hundreds of lines

11. `docs/manual/remote-desktop.md`: the enrollment path and the menu row, in
    the existing "Getting the password there" section → verify by reading it as
    someone with a second machine

12. `docs/manual/secrets.md`: `enroll` in the verb list → verify the list
    matches `nixarchy-secret --help`

13. `tests/install-matrix.py` and `tests/AGENTS.md`: name the hole — no check
    in this repo can reach a real RDP connection, because `checks.session`
    boots one desktop and a tunnel needs two → verify the row is there. A
    documented hole gets tested by a human; an undocumented one gets tested by
    a user

## Tests

Run one at a time, cheapest first. Check `gh run list` before any local build:
all four runners are on p620 and a local build competes with in-flight installs.

```sh
nix fmt -- --ci
nix run nixpkgs#statix -- check .
nix run nixpkgs#deadnix -- --fail .
nix build .#checks.x86_64-linux.secret-enroll --print-build-logs
nix build .#checks.x86_64-linux.menu-verbs   --print-build-logs
nix build .#nixarchy-secret --print-build-logs
```

Expected: all pass. `menu-verbs` is the one that proves the new row's action
names a verb `nixarchy-secret` actually accepts — the check exists because a
row once shipped calling `nixarchy-vm new` when the verb was `create`.

**Prove each new check fails first (§1), and put the failing output in the PR.**
For `secret-enroll`, the four breaks, each reverted after:

| break | must fail with |
|---|---|
| drop the `.creation_rules` append | host B cannot decrypt |
| drop the already-present test | the second run duplicates the entry |
| drop the host-key guard | a policy with an empty recipient |
| misspell `enroll` in the menu row | `menu-verbs` names the row and the verb |

After each break, **prove the break landed** — `git diff`, or grep the file for
what you meant to remove. A `sed -i` that matched nothing and a blind check are
indistinguishable from the exit status alone. Revert with
`git checkout HEAD -- <path>`, never `git checkout -- <path>`: a flake
evaluation needs the files staged, and restoring from the index restores the
break.

Commit a known-good baseline before starting the break loop.

## Rollback

Every step is additive. Nothing existing changes behaviour except step 4, which
only rewords a message that already refused.

- Before merge: `git checkout main`, delete the branch.
- After merge: revert the commit. `nixarchy-remote` and `enroll` disappear;
  `ensure_policy` returns to printing YAML without naming a command; the menu
  rows go with the fragment. No user data is touched by the revert.
- A user whose `.sops.yaml` was written by `enroll` keeps a valid policy: it is
  ordinary sops YAML with an inline recipient, and nothing in it depends on
  `enroll` existing.
