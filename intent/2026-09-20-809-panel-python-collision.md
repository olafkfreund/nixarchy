---
status: approved
issue: 809
author: olafkfreund
---

# Intent: a default panel's interpreter must not break a user's own profile

Closes #809.

## Problem

The GitLab pipelines and GitHub Actions panels are on by default and carry
`pkgs.python3` in their `defaultPluginSet` entries' `packages` (#770, #772),
because their `menu.py` is run by the panel and by the seeded
`SUPER + CTRL + ALT + P/A` binds. `modules/home.nix` concatenates those into
`home.packages`.

A user who keeps their own interpreter there — `python3.withPackages (ps: …)`,
which is the documented way to have a Python with libraries — now has two
different Pythons in one profile. Both provide `bin/idle3`, and Home Manager's
`buildEnv` refuses:

```
pkgs.buildEnv error: two given paths contain a conflicting subpath:
  `…-python3-3.14.7/bin/idle3' and `…-python3-3.14.7-env/bin/idle3'
```

What fails is `home-manager-path.drv`, so the **whole system closure** fails
with it and the machine cannot move to a new generation at all. Measured on
p620 against `281eef2`: as shipped the profile has
`python3-…-env`, `python3-…`, `python3-…`; with
`defaultPlugins.gitlab = false; github = false;` it has only the user's env.
The previous pin (`bf4c64c`, before those panels were defaults) builds.

Three things make this worse than an ordinary conflict:

- **It arrives without the user changing anything.** The panels became
  defaults; the user's Python was already there.
- **Nothing in the error names nixarchy, a panel, or a plugin.** It names
  `idle3`. The obvious reading is "my own config is wrong".
- **The failure is total.** A collision in `home.packages` is not a degraded
  panel; it is a rebuild that cannot complete, which is also how a user loses
  the ability to roll *forward* out of any other problem.

## Proposed outcome

- A machine with its own `python3.withPackages` in `home.packages` builds its
  profile with every default panel on, and keeps **its own** interpreter on
  PATH.
- A machine without one still gets an interpreter, so the panels and their
  `python3 …/menu.py` binds keep working.
- The rule is written down where the next `packages = [ … ]` will be added:
  a runtime tool nixarchy puts in somebody's profile must not out-rank what
  they installed themselves.
- A check fails if that rule is broken again, and it fails for the reason the
  user hits rather than a spelling of it.

## Affected users and systems

- **Every nixarchy desktop whose user keeps an interpreter in
  `home.packages`.** Today that is Python through the two panels; the same
  shape would apply to any future default that ships a language runtime.
- `modules/home.nix`: the two `defaultPluginSet` entries, and the rule's
  comment.
- `tests/options.nix`: the case that encodes it.
- p620 is the machine that found it and the one that proves the fix.

## Constraints

- **The interpreter has to stay reachable.** `pkgs/omarchy/default.nix` seeds
  `o.bind("SUPER + CTRL + ALT + P"/"A", …, "python3 $HOME/.config/omarchy/plugins/…/menu.py keys")`,
  which resolves `python3` from the session PATH. A fix that removes the
  interpreter from the profile has to give those binds one another way, in the
  same change.
- **No behaviour change for a user without their own Python.** They must not
  notice this.
- The fix is in nixarchy: the panels are upstream's and are not at fault for
  being run with an interpreter.
- Every new check is proved to fail first (§1).
- **This blocks #802's rollout on p620.** The devenv panel merged and is
  correct; it cannot be applied until the profile builds again.

## Open questions

1. **Which fix.** `lib.lowPrio` on the interpreter is one line and keeps the
   binds working, letting the user's own Python win a collision. Wrapping
   `menu.py` with its own interpreter where the panel is packaged
   (`gitlabPipelines`/`githubActions`) removes the interpreter from the
   profile entirely and pins the version the script was tested against, but
   the seeded binds and the panels' own QML both call `python3` by name, so it
   is a larger change. Recommendation: `lowPrio` now, wrapping as its own
   issue if the version ever matters.
2. **How far the rule goes.** Only `python3` collides today. `gh`, `glab`,
   `xdg-utils`, `jq`, `iproute2` and the devenv CLI are in the same lists and
   could collide with a user's own copy of any of them. Should every
   `packages` entry be low-priority by construction — enforced where
   `resolvedDefaults` is consumed rather than remembered at each site?
3. **What the check can see.** The failure happens when `home-manager-path` is
   *built*, not evaluated, so an evaluation-only assertion cannot reproduce it
   directly. Either the check builds a small profile that contains both
   interpreters, or it asserts the invariant (everything nixarchy adds carries
   a priority). The second is cheap and is the rule; the first is the symptom.
