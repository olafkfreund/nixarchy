---
status: approved
issue: 853
author: olafkfreund
---

# Intent: validating an installed plugin fails, and nothing says why that is fine

## Problem

`programs.nixarchy.plugins.<name>` installs each plugin as a symlink into
the store:

    ~/.config/omarchy/plugins/nixarchy.pkg -> /nix/store/…-nixarchy-pkg

Run upstream's validator on that folder, which is what a plugin author or
a user chasing a problem naturally does, and it refuses:

    omarchy-plugin-validate: symlinks are not allowed inside a plugin folder: …/nixarchy.pkg

It reads as "your plugin is broken". It isn't. Found on razer while
testing nixarchy-pkg (#853): the plugin loads and works, and the same
validator passes on the store path.

What isn't obvious from outside is that **nixarchy already runs that same
validator on every declared plugin at build time**, on the store path
(`modules/home.nix:412`), and fails the rebuild if it refuses. A
declared plugin that reaches `~/.config/omarchy/plugins` has already
passed. Only the installed link fails, and only because it is a link.
`docs/manual/configuration.md` says the rebuild validates. It doesn't
say that validating the installed folder by hand will fail, or that this
doesn't matter.

## Proposed outcome

Someone who validates an installed, declared plugin and sees that refusal
can find out in one place that it is expected, that the plugin was
already validated at build time, and what to validate instead if they
want to check again (the store path the link points to).

## Affected users and systems

- Plugin authors and users of `programs.nixarchy.plugins`.
- `docs/manual/configuration.md` (the plugins section), and possibly
  `modules/AGENTS.md`'s entry for the build-time check.
- nixarchy-pkg's README, which now points here (olafkfreund/nixarchy-pkg#30).

## Constraints

- **Don't patch upstream's validator.** The symlink rule is upstream's,
  and nixarchy's stance is to use upstream's own validator rather than a
  copy of its rules, so it can't drift at the next Omarchy bump.
- **Don't change how plugins are installed** just to satisfy a hand-run
  validation. A copy would rewrite the folder on every update and lose
  the store's read-only guarantee, to fix a message rather than a fault.
- Nothing may weaken the build-time check.

## Open questions

1. **Documentation only, or also a helper?** A line in the manual is
   enough to explain it. A tiny `omarchy plugin validate` wrapper that
   resolves a top-level store link first would make the hand-run check
   pass too, but it would be nixarchy owning a piece of upstream's
   command surface. The recommendation is documentation only.
2. **Close #853 with the docs change, or keep it open for upstream?** The
   rule is upstream's; if a top-level store link should be allowed, that's
   upstream's call, and an issue there would be the place to ask.
