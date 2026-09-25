---
status: approved
issue: 948
spec: spec/2026-09-24-948-text-size-on-managed-configs.md
---

# Plan: skip a managed terminal config, and say where to change it

> **Implementation blocked on a shape this plan got wrong. Not yet built.**
>
> Step 1 says to write the guard inline in `pkgs/omarchy/default.nix`'s build
> phase, beside the #963 patch. That phase is **already at the kernel's
> argument limit**: adding 48 lines to a 153 KB file produced
>
>     error: executing '/nix/store/...-bash-5.3p15/bin/bash':
>     Argument list too long
>
> with nothing in the message about the change that caused it. The file did not
> balloon -- `git diff --stat` says 48 insertions -- so this is a standing
> constraint on that build phase rather than anything about this patch.
>
> **The guard therefore has to live in its own file** (`writeText` /
> `writeShellScript`, or a `.patch` like `901-bar-keyed-layout.patch`) and be
> referenced from the phase, which is a different step 1 than the one approved.
> Two smaller traps found on the way, both worth knowing before the rewrite:
>
> - **`''` inside a Nix `''` string terminates it.** An empty shell string for a
>   blank `printf` line ends the Nix block instead, and the error points at a
>   line with nothing wrong on it.
> - **A backslash continuation must end its line.** `"" \  # comment` is not a
>   continuation, and the failure surfaces far from the comment.
>
> Everything above this note stands; only step 1's location changes.

## The approved decisions, carried over

1. **Skip and explain.** Not a nixarchy option rendering the size into seeded
   configs -- that is a feature, not this bug.
2. **One guard at the top of `set_terminal_size`**, not three patched `sed -i`
   lines: three `--replace-fail` needles are three things a bump can break
   independently.
3. **`--replace-fail`**, per `pkgs/AGENTS.md`, so a bump that rewords the needle
   fails the build rather than silently restoring the broken edit.
4. **Ours, not upstream's.** On Arch these are ordinary files in `$HOME`; our
   port made them read-only store symlinks. Same discriminator as #963.

## Confirmed while writing this, and it changes the message

**There is no nixarchy option to name.** The spec listed "naming the option" as
a risk to establish here rather than assume, and the answer is that nixarchy
**seeds** these files and never manages them -- grep finds no `alacritty.toml`,
`ghostty/config` or `foot.ini` in `modules/home.nix`'s seeding. On a stock
machine they are real files and the existing `sed -i` works.

They are symlinks on *this* machine because the user manages them with Home
Manager themselves:

```
~/.config/alacritty/alacritty.toml
  -> .../home-manager-files/.config/alacritty/alacritty.toml
```

So the message must point at **wherever the user declares it**, not at a
`programs.nixarchy.*` option. Inventing one would be section 2's "a setting the
tool does not read", printed at the user.

## Steps

1. **`pkgs/omarchy/default.nix`** -- `substituteInPlace ... --replace-fail` on
   `set_terminal_size() {` plus its `local pt="$1"`, inserting the guard: collect
   the four config paths that are symlinks resolving into `/nix/store`, and if
   any, print them, say the size is declared rather than edited, say the shell
   and GTK sizes still apply, and `return 0`.
   → verify by step 2.
2. **`tests/text-size-managed.nix`** -- a `runCommand` driving the real script
   against a fake `$HOME`. A PATH stub is not needed and would not be trusted:
   this script is upstream's and unwrapped, but the assertion is on the FILE,
   not on a command.

   | case | assert |
   |---|---|
   | configs are store symlinks | message names them; the target is **unchanged** |
   | configs are real files | falls through and the file **is** edited |

   **Section 1:** the managed case seen failing with the guard removed, and the
   assertion is *the file was not edited*, not that a message appeared.
3. **`pkgs/AGENTS.md`** -- a line under "Patching upstream" beside #963's,
   naming this as the second patch to an upstream script and why it is not sent
   upstream.

## Tests

| command | expected |
|---|---|
| `nix build .#checks.x86_64-linux.text-size-managed` | passes; two cases |
| `nix build .#omarchy` | builds; the `--replace-fail` lands |
| `nix fmt -- --ci`, statix, deadnix | clean |

## Rollback

`git revert`. The shipped script is upstream's again and the behaviour returns
to today's -- a `sed` error on a managed config. No state, no user file touched
in either direction.
