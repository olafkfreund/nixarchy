---
status: approved
issue: 809
intent: intent/2026-09-20-809-panel-python-collision.md
---

# Spec: a default's runtime tools lose to the user's own

## Decisions on the intent's open questions

| # | Question | Decision |
| --- | --- | --- |
| 1 | Which fix | **`lib.lowPrio`.** One line, the binds keep working, and the user's own interpreter wins. Wrapping `menu.py` with its own interpreter is the better long-term shape but a larger change (the seeded binds and the panels' QML both call `python3` by name); it becomes its own issue if the version ever matters. |
| 2 | How far the rule goes | **Every `packages` entry, by construction.** The priority is applied where `resolvedDefaults` is consumed in `modules/home.nix`, not remembered at each `defaultPluginSet` site, so a future entry cannot forget it. |
| 3 | What the check sees | **Both.** A cheap evaluation case in `checks.options` for the rule, and one new `checks.home-profile` that actually builds a profile holding both interpreters — the symptom. |

## Design

### The fix

`modules/home.nix` builds `home.packages` as

```nix
++ lib.concatMap (p: p.packages) (lib.attrValues resolvedDefaults);
```

That becomes `map lib.lowPrio` over the same list. One place, so every default
plugin's runtime tools — `gh`, `glab`, `python3`, `xdg-utils`, `jq`,
`iproute2`, `herdr`, the devenv CLI — are installed at low priority.

**What that means, and why it is right.** `buildEnv` resolves a collision by
priority instead of refusing, and the *lower* priority number wins;
`lib.lowPrio` raises the number, so anything the user put in `home.packages`
themselves (default priority) out-ranks it. A user with no copy of their own
is unaffected: there is nothing to collide with, and the tool is on PATH
exactly as before.

Measured before writing this, on this nixpkgs:

```
buildEnv [ python3, python3.withPackages(pytest) ]            -> refuses, conflicting subpath bin/idle3
buildEnv [ lowPrio python3, python3.withPackages(pytest) ]    -> builds
  its bin/python3 -> …-python3-3.14.7-env/bin/python3.14, and `import pytest` works
```

So the user keeps *their* interpreter, with their libraries, which is the half
that matters: a fix that merely stopped the error while leaving nixarchy's
bare interpreter first on PATH would break their tooling instead.

`lib.lowPrio` sets `meta.priority`; it does not change the derivation, so no
closure moves and nothing rebuilds.

### Where the rule is written down

- A comment at the `concatMap`, saying what it prevents and naming #809 — the
  next person adding to a `packages` list reads that line, not this file.
- `modules/AGENTS.md`, beside the default-plugins section: **anything nixarchy
  puts in somebody's profile loses to what they installed themselves.**
- The root `AGENTS.md` already gained the general lesson's neighbours in #802;
  this one is specific to the module, so it goes in `modules/AGENTS.md`.

### The checks

**`checks.options` (evaluation, cheap): `defaultRuntimeToolsLowPriority`.**
Every package that `resolvedDefaults` contributes to `home.packages` carries a
`meta.priority` above the default. `on` is a home with the defaults resolved;
`off` is the same assertion made to fail — the case is written so that a
future `packages` entry that skips the priority breaks it. This is the rule.

**`checks.home-profile` (build, new): the symptom.** A Home Manager profile
for a user who has `python3.withPackages (ps: [ ps.pytest ])` in
`home.packages`, with the default plugins on, is *built* — that is the
derivation that fails today (`home-manager-path`). The check also asserts
that the resulting `bin/python3` is the user's env rather than the bare
interpreter, because "it built" alone would pass if nixarchy's copy had won.

It is a `checks.<name>` and needs no workflow edit: `build.yml`'s `omarchy`
job builds every check no job claims, and a guard fails if one is unclaimed
and unbuilt (§4). Cost: one NixOS evaluation plus a `buildEnv`; the
interpreters are already in the store on any machine that has run `options`.

## Alternatives rejected

- **`lowPrio` at each `defaultPluginSet` site.** Same effect today, but it is
  a rule each future entry has to remember, which is how this happened.
- **Removing `python3` from the two panels' `packages`.** The seeded
  `SUPER + CTRL + ALT + P/A` binds run `python3 …/menu.py` from the session
  PATH, so this breaks them for a user without their own Python.
- **Wrapping `menu.py`.** The better long-term shape, and larger: both the
  binds and the panels' QML call `python3` by name, so all of those callers
  have to move together. Deferred to its own issue rather than smuggled into a
  fix for a broken rebuild.
- **Telling users to opt out of the panels** (`defaultPlugins.gitlab = false`).
  A workaround for a default that breaks their machine is not a fix.
- **An evaluation-only check.** The failure is at build time; an evaluation
  assertion alone would have passed on the day this shipped.

## Risks

- **A user who wants nixarchy's copy to win** now gets their own instead. That
  is the correct order — their `home.packages` is their instruction — and it
  only differs where they already had a copy.
- **`lowPrio` does not resolve a collision between two *low* priority
  packages.** Two defaults shipping different interpreters would still refuse.
  Nothing does today; `checks.home-profile` would catch it.
- **The new check is one more NixOS evaluation** in a repo where `options`
  already costs ~8 minutes and 11.5 GB. It is a much smaller machine (one user,
  no menu spec), and it is built by a job that already exists.
- **p620** is the host that proves it: the rebuild that fails today must
  succeed, with the devenv panel from #802 present and `import pytest` still
  working in the user's Python.

## Verification

Every new check is broken first (§1).

- `checks.home-profile` **without** the fix reproduces today's failure:
  `conflicting subpath … bin/idle3`. With the fix it builds, and its
  `bin/python3` resolves into the user's `-env`.
- `checks.options`' `defaultRuntimeToolsLowPriority` fails when the
  `concatMap` drops `lowPrio`.
- `nix fmt -- --ci`, statix, deadnix.
- By name: `options`, `home-profile`, `plugin`, `reference-toplevel`.
- **On p620, the real proof:** update the nixarchy input to this branch, build
  the p620 closure (which fails today), and confirm
  `python3 -c "import pytest"` still works from the built profile. Applying is
  the owner's.
