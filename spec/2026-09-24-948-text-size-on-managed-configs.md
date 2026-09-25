---
status: approved
issue: 948
intent: intent/2026-09-24-948-text-size-on-managed-configs.md
---

# Spec: skip a managed terminal config, and say which option to set

## The intent's questions, decided

**1. Skip and explain**, chosen by the maintainer. The alternative -- render the
font size into the seeded configs from a nixarchy option -- is a feature request
wearing a bug's clothes, and out of proportion to a font size.

**2. One guard, early in `set_terminal_size`**, not three patched `sed -i`
lines. Mine to decide, and the reason is `--replace-fail`: three needles are
three things an Omarchy bump can break independently, each failing the build
separately and each needing its own rewrite. One needle is one place to read and
one thing to re-anchor.

## Design

A guard at the top of `set_terminal_size` (`:136`): if the terminal configs it
would edit are symlinks into the store, say so and return before any `sed -i`.

```sh
set_terminal_size() {
  local pt="$1"
  # nixarchy patch (#948)
  local managed=()
  for f in ~/.config/alacritty/alacritty.toml ~/.config/ghostty/config \
           ~/.config/foot/foot.ini ~/.config/kitty/kitty.conf; do
    [ -L "$f" ] && case "$(readlink -f "$f")" in /nix/store/*) managed+=("$f") ;; esac
  done
  if (( ''${#managed[@]} )); then
    echo "Terminal font size is declared, not edited, on this machine:"
    printf '  %s\n' "''${managed[@]}"
    echo "Set it in your configuration and rebuild. The shell and GTK sizes"
    echo "below are applied as usual."
    return 0
  fi
  ...
```

**`readlink -f`, not the link's text**: a chain of symlinks ending in the store
is the ordinary Home Manager shape, and matching the first hop would miss it.

**`return 0`, not an error**: the shell and GTK parts of this command work and
must keep working. Today the user gets those *plus* a `sed` error; after this
they get those plus an instruction.

**A machine whose configs are real files is untouched.** Somebody who opted out
of the seeding, or edited their own, falls straight through to the existing
code. That is the state the check must assert in both directions.

## Alternatives rejected

| | why not |
|---|---|
| Patch the three `sed -i` lines | Three `--replace-fail` needles, independently breakable by a bump. |
| `sed --follow-symlinks -i` | Writes to the store target, which is equally read-only. Upstream's kitty branch already does this and it does not help here. |
| Let `sed -i` replace the symlink | Appears to work and silently takes the file out of Home Manager's management; the next rebuild fights it. Worse than the error. |
| Make the size a nixarchy option | The intent's second shape. A feature, not this bug. |
| Send it upstream | There is no bug upstream: on Arch these are ordinary files. |

## Risks

- **The needle.** `set_terminal_size() {` plus its first line is short and
  therefore likelier to survive a bump than a `sed` expression -- but if it
  moves, `--replace-fail` fails the build, which is the designed outcome.
- **Naming the option.** The message tells the user what to set. If nixarchy has
  no single option for terminal font size, the message must say what is true
  rather than invent one. **To establish in the plan, not assumed here.**
- **kitty is included** although its branch uses `--follow-symlinks`: it is
  equally unwritable, and leaving it out would produce the same error from one
  terminal only, which is harder to diagnose than all four.

## Verification

- A **`runCommand`** driving the real script against a fake `$HOME`: configs as
  store symlinks (skips, explains, and **does not** print a `sed` error), and
  configs as real files (falls through and edits them).
- **Section 1:** the managed case seen failing with the guard removed -- and the
  assertion is that the file was **not edited**, not that a message appeared.
- **What no check reaches:** whether the option the message names is the right
  advice. That is prose about another part of the system and only a human
  reading it can say.
