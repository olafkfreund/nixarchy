---
status: approved
issue: 853
intent: intent/2026-09-21-853-validate-installed-plugin.md
---

# Spec: say why validating an installed plugin fails, and that it doesn't matter

## Design

Documentation only (intent Q1). Two places, each saying the same thing to its own reader.

**`docs/manual/configuration.md`, "Declaring plugins in your configuration".** A bullet directly after "A broken manifest fails the rebuild", since it finishes that thought:

> - **Validating the installed folder by hand will refuse it, and that is expected.** A declared plugin is installed as a link into the store, and `omarchy-plugin-validate` refuses any symlink in a plugin folder, the folder itself included. The rebuild has already validated the plugin itself, the store path the link points to. To check it again: `omarchy plugin validate "$(readlink -f ~/.config/omarchy/plugins/<id>)"`.

The command is the whole workaround: `readlink -f` gives the store path, which is what the rebuild checked.

**`modules/AGENTS.md`, the `validatedPlugins` entry.** One paragraph after "Validated with upstream's own omarchy-plugin-validate…": the check runs on `plugin.src` (the store path), the installed result is a link, and upstream's rule refuses the link. So a hand-run validation of the installed folder failing is the expected consequence of the two, not a gap in this check. Anyone tempted to "fix" it by copying, or by patching upstream's rule, should read the intent's constraints first.

**#853** is closed by the merge, with a comment saying the rule is upstream's. If a top-level store link ought to be allowed, that's a question for Omarchy, not something nixarchy should decide (intent Q2).

## Alternatives rejected

- **A wrapper that resolves the link before validating.** It would make the hand-run check pass, but only by having nixarchy own part of upstream's command surface, and it would drift at the next Omarchy bump. That is the failure `validatedPlugins` was written to avoid.
- **Install plugins as copies.** Rewrites the folder on every update and loses the store's read-only guarantee, to change a message, not to fix a fault.
- **Patch upstream's symlink rule in nixarchy's Omarchy tree.** It's upstream's rule; a local patch is a second copy of their rules.

## Risks

None to a running system: no module, package or option changes. The only risk is the command in the bullet being wrong, so it is run as part of verification.

## Verification

1. On razer (a declared plugin is installed there): `omarchy plugin validate ~/.config/omarchy/plugins/nixarchy.pkg` fails with the symlink message, and `omarchy plugin validate "$(readlink -f ~/.config/omarchy/plugins/nixarchy.pkg)"` passes. The bullet's command, run exactly as written.
2. `nix flake check`, which covers whatever doc checks the flake runs.
3. Reading both passages in place, in the rendered manual if the docs site builds locally.
