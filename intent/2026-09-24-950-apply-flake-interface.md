---
status: approved
issue: 950
author: olafkfreund
---

# Intent: a stated way to ask which flake nixarchy rebuilds

## Problem

Nothing in nixarchy answers the question "which flake will `nixarchy-apply`
rebuild?", so a plugin that needs the answer reads it out of the script's
source. nixarchy-flatsnap's `flake()` does exactly that:

```bash
d=$(sed -n 's/^flake="\${NIXARCHY_FLAKE:-\(.*\)}"$/\1/p' "$(command -v nixarchy-apply)" | head -1)
```

That is fragile in a way worth spelling out, because it is worse than "the
line might get renamed". `nixarchy-apply` is **generated** (`modules/apps.nix`
:3283), and the line it matches is `modules/apps.nix:3317`:

```nix
flake="''${NIXARCHY_FLAKE:-${cfg.flake}}"
```

The `sed` anchors on `^flake="`, at column zero. That line sits sixteen spaces
deep in the Nix source and only reaches column zero because nixfmt strips the
string block's common indentation. Anything that changes that block's indent --
adding a conditional around it, or the heredoc trap in CLAUDE.md section 5 that
rewrote 2,600 lines of `tests/options.nix` -- moves the line without changing a
character of it, and the `sed` silently matches nothing. The plugin then falls
back to `/etc/nixos` and evaluates a different flake than the one apply
rebuilds. Since nixarchy-flatsnap#11 that fallback at least warns, but the
scraping is still load-bearing.

**Reading the tree for this turned up two problems the issue does not name,
and they change what "expose the flake" has to mean.**

**1. Two different resolution orders ship today, and most of the tree ignores
the option.** `programs.nixarchy.flake` is declared at `modules/apps.nix:1067`
with the default `/etc/nixos`. Only two places honour it:

| | |
|---|---|
| `modules/apps.nix:2559`, `:3317` | `''${NIXARCHY_FLAKE:-${cfg.flake}}` -- the option is the fallback |
| 17 occurrences, 14 files | `${NIXARCHY_FLAKE:-/etc/nixos}` -- a hardcoded literal |

**Two of the seventeen are in `modules/apps.nix` itself** (`:2055`, `:2500`),
four hundred lines from the two that honour `cfg.flake`. The rest are
`nixarchy-try:53`, `nixarchy-preview:39`,
`nixarchy-reinstall-iso:41`, `nixarchy-config-repo:25`, `nixarchy-home-backup`
:32, `omarchy-update:25`, `omarchy-system-factory-reset:59`, `pkgs/secret.nix`
:195, `pkgs/doctor.sh:597` and three `nixarchy-local-ai` sites.

So on a machine that sets `programs.nixarchy.flake = "/home/alice/nixos-config"`
and does not export `NIXARCHY_FLAKE`, `nixarchy-apply` rebuilds alice's flake
and `omarchy-update`, `nixarchy-preview` and `nixarchy-try` all reach for
`/etc/nixos`. That is a setting the tools do not read -- CLAUDE.md section 2's
quieter form -- and nothing reports it.

**2. Two of those scripts tell the user to set the option they ignore.**
`pkgs/doctor.sh:600` prints *"Set programs.nixarchy.flake, or export
NIXARCHY_FLAKE"* three lines after resolving `${NIXARCHY_FLAKE:-/etc/nixos}`
itself. `nixarchy-config-repo:434` does the same. A user who follows that
advice changes nothing and is given no way to find out.

The skills carry the literal too (`skills/nixos/SKILL.md:110` presents
`echo "${NIXARCHY_FLAKE:-/etc/nixos}"` as *"what Nixarchy's own commands
use"*), so the wrong answer is documented as the right one.

## Proposed outcome

Observable by the user and by a plugin:

- There is one command that prints the flake nixarchy will rebuild, and it is
  the answer every nixarchy command actually uses. A plugin calls it instead of
  parsing anything.
- Setting `programs.nixarchy.flake` and setting `NIXARCHY_FLAKE` produce the
  same answer from every nixarchy command, not from two of them.
- A machine where those disagree is a machine something can detect, rather than
  one where `omarchy-update` quietly rebuilds a different flake than
  `nixarchy-apply`.
- nixarchy-flatsnap's `flake()` drops its `sed`. nixarchy-pkg and any future
  panel that runs apply asks the same way.

Explicitly **not** in this outcome: changing what the default is, or what
`NIXARCHY_FLAKE` means. `/etc/nixos` stays the default and the environment
variable stays the override.

## Affected users and systems

- Anyone who has moved their flake off `/etc/nixos` -- 14 files answer with
  `/etc/nixos` and 2 answer with their path -- today they have a
  half-configured machine and no signal.
- External plugins that run a rebuild: nixarchy-flatsnap (found it),
  nixarchy-pkg, and the Rebuild panel.
- `pkgs/doctor.sh`, which is where a disagreement between the option and the
  scripts should probably surface.
- No installer impact expected: the installer writes the flake it generates.

## Constraints

- **Must not** turn into a second source of truth. The option is the
  declaration; whatever is added reports it, and does not get to disagree.
- **Must not** require a rebuild to answer. A plugin asks at run time, on a
  machine that is already built.
- Any script this touches lives in `pkgs/omarchy/nix-bin/` or is generated from
  `modules/apps.nix` -- both nixarchy's own, so no upstream routing question
  (unlike #948 and #953).
- `writeShellApplication` builds a strict PATH from `runtimeInputs`; anything
  new the resolver calls has to be declared there or it is a runtime failure no
  build catches.
- `modules/apps.nix` has been named as a hot file by another agent's team in
  the past. Worth re-checking on the bus before the plan, not before the intent.

## Open questions

1. **Which shape?** The issue offers two, and they are not equivalent:
   - `nixarchy-apply --print-flake`, which prints the resolved path and exits.
     No new file, no activation step; but every caller must have
     `nixarchy-apply` on PATH and must spawn it.
   - A known file, e.g. `/etc/nixarchy/flake`, written by the module. Cheaper
     to read, readable without nixarchy on PATH, and survives `nixarchy-apply`
     being renamed -- but it is a second artifact that can go stale against the
     option if anything ever writes it from elsewhere.

   My inclination is the file, *because* of problem 1 above: fourteen scripts
   need the answer, and `$(nixarchy-apply --print-flake)` in fourteen places is
   fourteen subprocess spawns and fourteen chances to get the fallback wrong,
   whereas a file is one `cat` with one literal fallback. But this is the
   decision the intent exists to put to you rather than assume.

2. **How far does the fix reach?** Three defensible scopes:
   - (a) the interface only -- add the accessor, leave the fourteen sites
     alone. Closes #950 as filed. Leaves the option still ignored by most of
     the tree.
   - (b) the interface, and convert the fourteen sites to use it.
   - (c) (b) plus a doctor check that reports when the option and the scripts
     would disagree, plus fixing the two scripts that advise setting an option
     they ignore.

   (a) is what the issue asks for. I think (a) alone ships a correct interface
   onto an incorrect machine, and the next person to find the real bug finds it
   the way this one was found -- on hardware. But (c) is meaningfully more
   work and more review, and it is your call whether it is one task or two
   issues.

3. **Is the option/literal split deliberate?** I could not find a comment
   saying so, and the two sites that honour `cfg.flake` are the two newest.
   It reads like drift rather than a decision, but if there is a reason those
   fourteen should pin `/etc/nixos`, that reason kills scope (b) and (c) and I
   have not found it.

## Not in scope

- `modules/auto-update.nix:59` declares its own `flake` option. Whether that
  should be the same value is a separate question and a separate issue.
- The manual and the skills documenting `${NIXARCHY_FLAKE:-/etc/nixos}` as the
  answer. They follow whatever is decided here; changing them first would
  document an intention rather than a behaviour.
