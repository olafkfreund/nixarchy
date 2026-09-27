---
status: approved
issue: 1030
author: olafkfreund
---

# Intent: a feature nothing builds is a feature nobody has built

## Problem

`programs.nixarchy.services.hypr-rdp` has been **unbuildable since
2026-09-15** and nothing noticed. nixarchy pins `sops-nix` at `a8627b21`
(2026-08-13); nixpkgs removed `buildGo125Module` on 2026-09-15; the pinned
`sops-install-secrets` still calls it. So any configuration declaring a sops
secret — which this feature requires — dies with

    error: Go 1.25 is end-of-life, and 'buildGo125Module' has been removed.

an error naming Go, not sops, not nixarchy, and not remote desktop.

That is twelve days of a shipped feature that could not be turned on, with a
manual page describing it, two menu rows offering it, and a green suite.

**And it is not the only one it hid.** Configuring RDP across three real
machines today surfaced three defects in one feature: this, #1031 (the
daemon cannot create its headless output on Hyprland 0.56), and #1033
(enabling it takes effect only at next login, so the service is not running
and the menu row is absent, with nothing saying why). Every one was found by
using it. None was found by CI.

## Why the existing coverage missed it

`tests/options.nix` is not thin here. It has a sops fixture (`sopsDecl`), an
`rdpOn` fixture that enables hypr-rdp **with a real `passwordSecret`**, and
cases for the unit, the template, the firewall and both refusals.

It still could not catch this, and the reason is written in its own comment:

> Read as a list of failed assertions rather than by forcing
> `system.build.toplevel`: the point is that THIS assertion fires, and a
> config that fails to build for some unrelated reason would look identical
> from outside.

That reasoning is correct for what it was written about. Its consequence is
that **`checks.options` never forces the closure**, so a package that cannot
be built — or, as here, cannot even be evaluated — is invisible to it.

Confirmed rather than reasoned about. Forcing the drvPath of a reference host
with hypr-rdp enabled throws the Go error today, at evaluation, with no build
at all:

    nix eval … reference.extendModules { hypr-rdp on; sops secret } …
      .config.system.build.toplevel.drvPath
    → error: Go 1.25 is end-of-life …

So the missing check costs an **evaluation**, not a VM.

## Proposed outcome

- the `sops-nix` pin builds again, and `hypr-rdp` can be enabled
- a check goes red when a configuration with `hypr-rdp` enabled stops being
  buildable, whatever the cause — a stale input, a removed builder, a renamed
  option
- it costs an evaluation, so it can run on every pull request
- what it still cannot see is written down rather than implied

## Affected users and systems

- anyone enabling remote desktop; today, that is nobody successfully
- `flake.nix`'s `sops-nix` input, and therefore every host's closure hash
- a new `checks.*` entry, run by `build.yml`'s generated step without a
  workflow edit
- `tests/AGENTS.md` and `tests/install-matrix.py`, which already name the
  two-machine hole and should name this narrower one too

## Constraints

**The new check must not join `checks.options`.** That check peaks at 12.9 GB
on the hosted runner and is the subject of #747; adding a whole system
closure evaluation to it is the wrong place, however convenient the fixtures
are. Its own derivation, its own evaluation.

**It must force the closure, not inspect the tree.** Inspecting is what
`options.nix` already does and is exactly what could not see this.

**It must not need a VM.** The evidence above is that it does not, and a check
that needs one would be nightly-only and would not have caught this on the
pull request that introduced it.

**Bumping the pin changes every host's closure hash.** That is unavoidable
and worth stating: this is not a no-op change.

**No new option, no behaviour change.** The feature is meant to work as
documented; nothing about what it does should move.

## Open questions

1. **How much should the check cover?** The narrow version forces one
   configuration with hypr-rdp enabled. The broad version forces one per
   bundled service, which would catch the next stale input in whichever
   feature it lands in — and costs an evaluation each. Narrow now, or the
   pattern immediately?

2. **Should it assert anything beyond "it builds"?** Once the closure is
   forced, asserting the unit exists and points at the rendered config is
   nearly free — but `options.nix` already asserts both, and duplicating them
   makes two places to update.

3. **What about #1031 and #1033?** Neither is reachable this way: one needs a
   live compositor, the other needs a session that postdates the rebuild.
   They belong in `checks.session` or `pkgs/verify.sh`, and the honest move
   is to say which rather than let this check imply the feature is covered.
