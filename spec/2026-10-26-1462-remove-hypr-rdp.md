---
status: approved
issue: 1462
intent: intent/2026-10-26-1462-remove-hypr-rdp.md
---

# Spec: remove hypr-rdp

## Design

**One removal line replaces the module.** `modules/services/hypr-rdp.nix`
defines 10 options under `programs.nixarchy.services.hypr-rdp` (lines
158-277). It is replaced, at its import in `modules/services/default.nix:77`,
by:

```nix
(inputs.nixpkgs.lib.mkRemovedOptionModule [ "programs" "nixarchy" "services" "hypr-rdp" ] ''
  hypr-rdp was removed from nixarchy (#1462). For a remote desktop between Hyprland machines use gliff,
  installed by default (Setup > Remote desktop > Connect with gliff). You can also delete
  sops.secrets.hypr-rdp-password and its encrypted value; sops-nix itself is unchanged.
'')
```

`mkRemovedOptionModule` declares one hidden option. Any definition under it
fails the rebuild with "no longer has any effect" plus this text. A machine
that never set it gains nothing (Mode A). The repo has no earlier use of it.

**Two side effects of a hidden option, each fixed in one line:**

- `tests/doc-options.nix` accepts any documented path under an existing
  option. It must skip options with `visible = false`, or stale
  `hypr-rdp.enable` mentions in the docs would pass.
- `.github/scripts/release-notes-options.nix` must skip `visible = false`, or
  the release notes would list the removed option as new.

**sops-nix stays, and so does its probe.** `tests/hypr-rdp-builds.nix`
becomes `tests/sops-evaluates.nix`. It takes the `reference` configuration,
adds one sops secret, and forces `setupSecrets`'s text length, which forces
`sops-install-secrets`. Nothing else in the suite forces it:

- `checks.options` only tests that the attributes exist;
- `secret-enroll` and `secret-new` run the `sops` command-line tool;
- `checks.session` loses its only secret in this change.

It is shown red against the sops-nix pin of #1030. #1459's `data/pin-fix.nix`
probe moves to it.

**`nixarchy-remote` goes; freerdp stays.**

- `nixarchy-remote` goes: its `connect` verb needs an RDP server at the far
  end, which was hypr-rdp. That means its script, its bin-ledger row and its
  menu rows. `nixarchy remote` then prints a pointer to gliff, like the retired
  `box` verb (`modules/apps.nix:3642`).
- freerdp, a general client, stays in `data/apps.nix`. Only its note changes,
  so no derived count moves.

**Docs.** No page is deleted.

- `docs/manual/remote-desktop.md` keeps its gliff half and loses the RDP
  sections.
- `configuration.md`, `security.md`, `secrets.md`, `README.md`, `llms.txt`,
  `docs/internals/flake.md` and `workflows.md` lose their hypr-rdp mentions.
- The anchor that `flake.nix:138` points at stays.
- The history folders `intent/`, `spec/` and `plan/` are not edited.

**CI.**

- `cache-allowlist.sh` loses `.#hypr-rdp`.
- `build.yml` loses system-checks' "Build hypr-rdp, which checks.options
  needs" step, about 11 minutes cold.
- system-build's step that also built hypr-rdp keeps only the box image.

## Alternatives rejected

- **Keep the module, off by default:** it still costs the bump-time build in
  `checks.options` and the allowlist, which is the cost this removes.
- **Delete the option with no removal line:** a configuration that set it
  fails with an unexplained "option does not exist".
- **Remove sops-nix too:** it is the general secrets mechanism. Every machine
  imports it, and `nixarchy secret` and the editor integration use it.
- **Remove freerdp:** it is a client with its own users, and removing it would
  move the app counts for no gain.

## Risks

- **`pkgs/secret.nix:153` walks `programs.nixarchy.services`,** so it now
  reaches the throwing option. `tryV` catches throws; `checks.secret-new`
  proves it.
- **#1459 order:** whichever PR lands second updates the pin-fix probe, and
  `checks.pin-fix` fails until it does. That failure is loud, not silent.
- **#1461 collides in `build.yml`:** this lands first.

## Verification

- `grep` for `hypr-rdp`, `nixarchy-remote` and `rdp`, outside the history
  folders, finds only the deliberate lines.
- These checks build, under the evaluation and cheap tiers:
  - `checks.sops-evaluates`
  - `options` (only with CI idle)
  - `doc-options`
  - `docs-lists`
  - `bin-ledger`
  - `menu-verbs`
  - `test-registration`
  - `release-notes`
  - `secret-new`
  - `secret-enroll`
  - `config-repo-ownership`
  - `cache-budget`
  - `cache-entries`
- `readme-counts.sh --check` shows no drift.
- **§1 proofs:**
  - `sops-evaluates` red on the old sops-nix pin;
  - the removal case in `checks.options` red without the removal line;
  - `doc-options` red on a stale `hypr-rdp.enable` mention once the
    visibility filter is in.
- `checks.session` needs KVM and is left to CI.
