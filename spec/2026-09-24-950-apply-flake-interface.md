---
status: approved
issue: 950
intent: intent/2026-09-24-950-apply-flake-interface.md
---

# Spec: an environment-independent way to ask which flake nixarchy rebuilds

## What the corrected intent leaves

The intent was approved and then corrected: `programs.nixarchy.flake` is
**not** ignored. `modules/nixos.nix:1172` sets `NIXARCHY_FLAKE = cfg.flake` in
`environment.sessionVariables`, so inside a session all 17
`${NIXARCHY_FLAKE:-/etc/nixos}` sites already resolve to the option.

Two things survive that correction, and this spec addresses only those:

1. **`sessionVariables` exist only in a session.** A systemd unit, a `sudo`
   that does not take a login shell, and any process spawned outside the
   session get `/etc/nixos` whatever the option says.
2. **There is no way to ask.** nixarchy-flatsnap `sed`s the answer out of
   `nixarchy-apply`'s source, anchored on `^flake="` at column zero -- a
   position that holds only because nixfmt strips the generating block's common
   indent.

## Design

**Write the resolved flake path to `/etc/nixarchy/flake`, declaratively.**

```nix
environment.etc."nixarchy/flake".text = cfg.flake;
```

Beside the existing `environment.etc."nixarchy/managed"` in
`modules/nixos.nix:1426`, whose own register entry is titled *"The ownership
marker, for the shell tools that cannot ask the module system anything"*
(`modules/AGENTS.md:448`). That is this issue's problem statement, already
written down, already solved once, with the mechanism and the directory in
place. This is a second file in an established pattern, not a new interface.

The reasoning that entry gives transfers exactly: it is in the closure, it is
rewritten by every rebuild, and a machine whose `programs.nixarchy.flake`
changes gets the new value in the same switch that changed it. A file written
once at install time could not say that -- it would survive being wrong.

**The resolution order is unchanged and stays what it is today:**
`NIXARCHY_FLAKE` if set, else the option. The file carries the option's value,
so a reader spells it:

```sh
flake="${NIXARCHY_FLAKE:-$(cat /etc/nixarchy/flake 2>/dev/null || echo /etc/nixos)}"
```

An external plugin that cannot rely on the environment reads the file directly
and needs nothing of ours on `PATH`.

## What this deliberately does not do

- **It does not convert the 17 sites.** Scope (b) is withdrawn: they already
  resolve correctly wherever the session environment exists, which is every
  context a user is in. Converting them would be a large mechanical diff whose
  user-visible effect is confined to contexts this spec does not claim to have
  surveyed. If a specific one is shown to run outside a session, it is a
  one-line change then, with a reason attached.
- **It adds no `--print-flake` flag.** A flag needs `nixarchy-apply` on `PATH`
  and a subprocess; the file needs neither, and the precedent is a file.
- **It does not change the default.** `/etc/nixos` stays the default and
  `NIXARCHY_FLAKE` stays the override.
- **It does not touch `modules/auto-update.nix:59`**, which declares its own
  `flake` option. Whether those should be one value is a separate question.

## Alternatives rejected

| | why not |
|---|---|
| `nixarchy-apply --print-flake` | Requires our binary on `PATH` and a process spawn per query. The file is one `read`, works from a unit, and survives the command being renamed -- which is the failure mode the issue is about. |
| Convert all 17 literals | Withdrawn above: no user-visible effect, and the intent's claim that motivated it was false. |
| Guard nothing, document the scrape | Leaves an external plugin depending on our source layout. The `^flake="` anchor holds only through nixfmt's indent stripping, so an unrelated refactor breaks a different repository silently. |
| Emit it into `sessionVariables` only (status quo) | That is the bug. |

## Risks

- **A second source of truth.** The file is generated from `cfg.flake` in the
  same module that declares it, so it cannot disagree; but anything that later
  writes `/etc/nixarchy/flake` from elsewhere would break that. Mitigated by
  the same property `nixarchy/managed` relies on: `environment.etc` is
  read-only in the store and regenerated per rebuild.
- **Mode A.** A machine importing `nixosModules.nixarchy` gains one file in
  `/etc`. It is content-only, no unit, no activation, and `cfg.flake` has a
  default, so it is defined on every machine. `tests/options.nix` asserts the
  off state as well as the on state, and the off state is the one a refactor
  breaks quietly.
- **Reproducibility of the machine's own toplevel.** `installer/host.nix:115`
  records that putting an *identity-dependent* value into `/etc` made the
  installed system's toplevel unmatchable against anything built elsewhere, and
  `checks.install` went red the moment it was added. That entry is about
  `nix.registry.nixarchy.flake = inputs.self`, not this option, and the hazard
  does not transfer: `cfg.flake` is a plain `str` (`modules/apps.nix:1082`,
  default `/etc/nixos`) that resolves to the same characters wherever it is
  evaluated, whereas `self` is a store path locally and a github pin on an
  installed machine. Named here because the shape is close enough that a
  reviewer should see it ruled out rather than unconsidered, and because
  `checks.install` is the check that would report it.
- **The installer** sets `programs.nixarchy.flake` for the machine it
  generates, so the file should follow with no installer change. To be
  confirmed in the plan by reading `installer/host.nix`, not assumed.

## Verification

- **`checks.options`**, a case in both states: the file's content equals
  `cfg.flake` when the option is set to a non-default path, and equals
  `/etc/nixos` on a default machine. Section 1: the case must go **red with the
  `environment.etc` line removed**, and that failing output goes in the PR.
  The trap to avoid is asserting on something the module produces anyway --
  the #942 case passed against a deliberate break for exactly that reason, so
  the assertion reads the file's *text*, not its presence.
- **What no check here reaches**, stated rather than implied: that a systemd
  unit or a `sudo` invocation actually reads the right value. That needs a
  real machine with `programs.nixarchy.flake` set away from the default.
  It goes in `tests/AGENTS.md` as a documented hole, and is checked by hand on
  razer, which already has a non-default flake.
- **nixarchy-flatsnap** dropping its `sed` is a separate change in a separate
  repository and is **not** part of this issue's verification. Filing anything
  there is not done unprompted (section 11).

## Open question

`cfg.flake` is a `str` with no trailing-newline discipline.
`environment.etc.<name>.text` appends none, so `cat` returns the path with no
newline and `$(cat ...)` is clean either way. Worth one line in the plan to
decide deliberately rather than inherit it -- I propose no trailing newline,
matching what `$(...)` would strip anyway.
