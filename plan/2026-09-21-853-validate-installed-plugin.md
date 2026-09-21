---
status: approved
issue: 853
spec: spec/2026-09-21-853-validate-installed-plugin.md
---

# Plan: say why validating an installed plugin fails, and that it doesn't matter

## Approved decisions (from the spec)

- Documentation only. No module, package, option or upstream change.
- `docs/manual/configuration.md`: one bullet directly after "A broken manifest fails the rebuild" (`:149-152`). It says hand-validating the installed folder refuses it because the folder is a link into the store, that the rebuild already validated the store path it points to, and gives the command to check it again: `omarchy plugin validate "$(readlink -f ~/.config/omarchy/plugins/<id>)"`.
- `modules/AGENTS.md`, the `validatedPlugins` entry: one paragraph after "Validated with upstream's own omarchy-plugin-validate…" (`:817-822`). The check runs on `plugin.src`, the install is a link, and upstream refuses links, so a hand-run failure on the installed folder is expected and not a gap. Copying or patching upstream's rule are the rejected alternatives.
- Rejected: a validator wrapper, installing copies, patching upstream's symlink rule.
- #853 closes with the merge; the PR says a top-level store link is upstream Omarchy's call.

## Steps

1. **`docs/manual/configuration.md`**: insert the bullet after line 152 (the end of "A broken manifest fails the rebuild"), wrapped to the file's width, same `- **…**` style as its neighbours.
   -> verify by reading the section in place: the bullet finishes the build-time-validation thought and names the command.

2. **`modules/AGENTS.md`**: insert the paragraph after line 822 (the end of "Validated with upstream's own…"), inside the same entry, before the pacman subsection's anchor.
   -> verify by reading; no anchor ids (`<a id=…>`) change, so no `# Why:` link breaks.

3. **Run the bullet's command exactly as written** on razer, where a declared plugin is installed:
   - `omarchy plugin validate ~/.config/omarchy/plugins/nixarchy.pkg` → the symlink refusal;
   - `omarchy plugin validate "$(readlink -f ~/.config/omarchy/plugins/nixarchy.pkg)"` → passes.
   -> verify by both outcomes.

4. **PR** from `docs/853-validate-installed-plugin`, linking intent, spec and plan, `Closes #853`, with the upstream note.
   -> verify by CI green.

## Tests

    # on razer
    omarchy plugin validate ~/.config/omarchy/plugins/nixarchy.pkg                      # refused (symlink)
    omarchy plugin validate "$(readlink -f ~/.config/omarchy/plugins/nixarchy.pkg)"     # ok

No flake check covers prose docs (`doc-options` is the options reference), so reading the two passages in place is the check. CI runs on the PR.

## Rollback

`git revert` the docs commit. Nothing else changes.
