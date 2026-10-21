---
status: approved
issue: 1407
intent: intent/2026-10-21-1407-version-pin-check.md
---

# Spec: a hand-pinned Omarchy bump with a stale version string fails a check

## Design

`tests/omarchy-version-label.nix` gains one assertion. It receives the
parsed lock from its `flake.nix` call (~:2525):

```nix
lock = builtins.fromJSON (builtins.readFile ./flake.lock);
```

The pin is `lock.nodes.omarchy.original`.

- **A tag pin (stable).** When `original ? ref`, the check asserts
  `original.ref == "v" + omarchyVersion`. Today that is
  `v4.5.0-rc1` against `4.5.0-rc1`.
- **A rev pin (edge).** Otherwise it asserts that `omarchyVersion`
  matches `edge-[0-9]{8}-<first 7 of lock.nodes.omarchy.locked.rev>`.
  Edge's line 540 is written by `omarchy-edge.yml` as
  `edge-20261021-0a7beb7`, so a hand repin that forgets it fails the
  same way.
- **The failure message names both values and the file to fix:**
  "flake.nix:540 says 4.0.6, but flake.lock pins v4.5.0-rc1".

The lock, not `flake.nix`'s text, is the source: it is what was
evaluated. The assertion sits beside the existing wiring assertion
(`omarchy.version == omarchyVersion`), so this one check now owns the
whole chain: pin → version → package.

## Alternatives rejected

- **A separate `checks.omarchy-pin-version`:** this check already owns
  the label (#1371), and the intent says to extend it.
- **Parsing `flake.nix` text:** that is what `omarchy.yml` does at bump
  time. The lock is authoritative and needs no regex.
- **Deriving `omarchyVersion` from the lock automatically:** it would
  remove the duplicate, but the version also feeds `release.yml`'s
  guard, the ISO label and the release notes as a literal. That is a
  wider change than this bug.

## Risks

- **A dev pin** (`nixarchy channel omarchy dev`, a `git+file` input)
  has neither form. Those builds evaluate in the user's own flake, not
  in this repo's `checks`, so the check never sees them. Stated in the
  check's comment.
- **Edge's workflow writing a different shape** would turn the edge
  form red. That is the right outcome: the edge run fails loudly and
  names the line.

## Verification (§1)

| case | red | green |
|---|---|---|
| tag pin | url and lock at `v4.5.0-rc1`, `omarchyVersion = "4.0.6"` (#1403's measured state): the new assertion fails, naming both | `4.5.0-rc1` |
| rev pin | on `origin/edge`, `omarchyVersion = "edge-20261021-0000000"` against lock rev 0a7beb7: fails | edge's real value passes |
| wiring | the existing assertion still holds | — |

The edge case is proven in a scratch worktree off `origin/edge` with
this change cherry-picked. It is not carried there now: edge receives it
through its nightly merge of `main`.
