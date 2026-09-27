---
status: draft
issue: 1030
intent: intent/2026-09-27-1030-hypr-rdp-builds.md
---

# Spec: force the closure of a host that has remote desktop on

## The open questions, settled

1. **Narrow.** One configuration, hypr-rdp enabled. The per-service pattern is
   attractive and costs an evaluation each; this one exists because a feature
   was broken for twelve days, and the narrow version would have caught it on
   the day. Widening later is copying a `let` binding.
2. **Nothing beyond "it builds".** `options.nix` already asserts the unit
   exists, the template renders and the `ExecStart` points at it. Repeating
   them here makes two places to update and buys nothing.
3. **#1031 and #1033 are out of reach and get said so**, in
   `tests/AGENTS.md` beside the two-machine note that is already there.

## Design

### Two halves, one pull request

**Bump `sops-nix`** in `flake.nix` from `a8627b21` (2026-08-13) to a revision
whose `sops-install-secrets` builds. That is the fix.

**Add `checks.hypr-rdp-builds`** — a `runCommand` whose only job is to force
the drvPath of a reference host with hypr-rdp enabled and a sops secret
declared. That is what keeps it fixed.

### Why forcing a drvPath is the whole check

    reference.extendModules { hypr-rdp on; sops secret }
      .config.system.build.toplevel.drvPath

Evaluating that string today throws:

    error: Go 1.25 is end-of-life, and 'buildGo125Module' has been removed.

No build, no VM, no runner minutes — the failure is at evaluation, because
`buildGo125Module` is an alias that `throw`s. So the check is: evaluate the
drvPath, write it to `$out`. If the closure cannot be described, the check
cannot be built.

That also means it catches more than this bug. Anything that makes a host
with remote desktop enabled undescribable — a removed builder, a renamed
option, an input that no longer evaluates — fails here, and fails naming the
feature rather than naming Go.

### Where it lives

Its own file, `tests/hypr-rdp-builds.nix`, and its own `checks` entry.
**Not in `checks.options`**, whose fixtures are tempting and whose peak is
12.9 GB on the hosted runner (#747). A whole system closure evaluation does
not belong in the check that is already the memory problem.

No workflow edit: `build.yml`'s `omarchy` job builds every check not on the
`claimed` or `exempt` lists, which this is not.

### The fixture

`reference` extended with hypr-rdp on and the same shape of sops declaration
`options.nix` already uses — `validateSopsFiles = false`, a `keyFile`, a
`defaultSopsFile` pointing at a file in the tree, one secret. It never
decrypts anything; it only has to make the module's assertions pass so the
closure is describable.

## Alternatives rejected

**A case in `checks.options`.** The obvious home, and the wrong one: its
comment explains that it deliberately does not force `system.build.toplevel`,
and #747 is about its memory peak. Adding a closure evaluation there trades a
cheap check for an expensive one.

**A `checks.session` case.** It would catch #1033 as well, and it needs a
booted desktop — so it could not have caught this on the pull request that
broke it, which is the whole point. Worth doing separately for the runtime
half.

**Building the toplevel rather than evaluating it.** The failure is at
evaluation, so building adds minutes and catches nothing extra here. A
genuine build failure would still be caught by `reference-toplevel`.

**Only bumping the pin.** Fixes today, guarantees nothing. The pin will go
stale again — that is what pins do.

## Risks

- **The bump changes every host's closure hash.** Unavoidable, and worth
  saying out loud rather than discovering in a diff.
- **A newer `sops-nix` could break something else.** Mitigated by the
  existing checks that build closures — `reference-toplevel`, `vm-toplevel`,
  `system` — all of which run on the same pull request.
- **The check can pass while the feature is broken**, and it must not be read
  as coverage. It proves the closure is describable. It says nothing about
  the daemon starting (#1031) or the session picking it up (#1033).
- **A fixture drifting from the real module** — if `hypr-rdp` grows a required
  option, the fixture needs it too, and the failure will be the check rather
  than a user. That is the right direction.

## Verification

| what | how | break it by |
|---|---|---|
| the check goes red on an unbuildable closure | it is red **right now**, before the bump, with the Go error | — this is the rare check whose red state exists before it is written |
| it goes green after the bump | run it | reverting the bump |
| it is not a no-op | remove `hypr-rdp.enable` from the fixture and confirm the pre-bump red disappears | — proves the enable is what forces sops |
| nothing else broke | `reference-toplevel`, `vm-toplevel`, `options`, `system` | — |

The first row is unusual and worth stating plainly: **this check can be shown
failing against the bug it was written for, on the real tree, before the fix
lands.** That is stronger than a synthetic break, and it is only possible
because the bug is still present.

## Open questions

1. **Which `sops-nix` revision?** `5efb5a6f` (2026-09-27) builds — verified
   downstream in the config repo via a `follows`. Pin that, or take whatever
   `nix flake update sops-nix` resolves on the day?
2. **Should `review-pins` learn about this?** It already tracks `sops-nix` by
   rev (`tests/review-pins.nix:111`). A pin that has gone stale enough to
   stop building is a different question from a pin that has merely moved,
   and the nightly may be the place to notice it earlier.
