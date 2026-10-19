---
status: draft
issue: 1371
intent: intent/2026-10-19-1371-dev-version-label.md
---

# Spec: a dev machine reports the Omarchy commit it is running

## Design

### 1. A small pure function: `pkgs/omarchy/version-label.nix`

```nix
# #1371: the Omarchy commit nixarchy pins keeps its release/edge label; any
# other commit (the dev channel, or an override) is named after itself.
{ version, pinnedRev, input }:
let
  rev = input.rev or null;
  date = builtins.substring 0 8 (input.lastModifiedDate or "unknown");
  short = input.shortRev or "unknown";
in
if rev != null && rev == pinnedRev then version else "dev-${date}-${short}"
```

- `pinnedRev` comes from **nixarchy's own `flake.lock`**: the file inside
  nixarchy's source, which a consumer's overrides never change. It is
  `(lock.nodes.${lock.nodes.root.inputs.omarchy}).locked.rev`, read with
  `builtins.fromJSON (builtins.readFile ./flake.lock)`. On `main` today that
  is `94a8fbc2…` (v4.0.5).
- `input` is the `omarchy` flake input as evaluated, the commit actually
  being built. Unless overridden, its `rev` equals `pinnedRev`, so stable and
  edge keep `4.0.5` and `edge-<date>-<rev>` exactly as now.
- A `path:` override has no `rev` (the intent's second question), which gives
  `dev-<date>-unknown`, or `dev-unknown-unknown` with no date either. It never
  throws.
- `rev != null &&`: a rev-less input must not equal a rev-less pin by
  accident.

### 2. `flake.nix`, at the use site only

The `omarchy = final.callPackage ./pkgs/omarchy { … version = omarchyVersion; … }`
call (around line 911) becomes:

```nix
version = import ./pkgs/omarchy/version-label.nix {
  version = omarchyVersion;
  pinnedRev = ownLock.nodes.${ownLock.nodes.root.inputs.omarchy}.locked.rev or null;
  input = omarchy;
};
```

with `ownLock = builtins.fromJSON (builtins.readFile ./flake.lock);`
defined beside `nixarchyRev` (line 630), which is not a line `edge`
changes. `omarchyVersion` itself (line 537, which differs on `edge`) is
**not touched**, so the edge workflow's literal and edge's merge of `main`
both stay clean. `omarchy-nvim-config` keeps `omarchyVersion`: its version
names the config's provenance, not the running commit.

Everything that prints a version follows from the package's `version`:
`omarchy-version`'s substitution (`echo "${version}"`), `nixarchy version`,
and the About screen.

### 3. Check: `checks.omarchy-version-label` (evaluation-only)

`tests/omarchy-version-label.nix` calls the function with fake inputs and
asserts, with named messages:

| `input` | expected |
|---|---|
| `rev` = the pin | the literal (`4.0.5`) |
| another rev, `lastModifiedDate = "20261019180000"`, `shortRev = "2d3aa60"` | `dev-20261019-2d3aa60` |
| no `rev` (a path input) | `dev-unknown-unknown` |
| `rev = null`, pin `null` | not the literal |

It also asserts the wiring: the flake's own `self.packages.<sys>.omarchy.version`
equals `omarchyVersion` (not overridden, so it must be unchanged). That makes
stable and edge provably unaffected.

## Alternatives rejected

- **Have the edge workflow write a second literal** (the pinned rev): it adds
  automation, and two literals to keep in step. The lock already has it.
- **Compute the label from the input alone** (always `<date>-<rev>`): stable
  would stop saying `4.0.5`.
- **Detect dev from the user's flake:** nixarchy cannot see the consumer's
  flake. The input's rev is the only signal that reaches it, and it is enough.

## Risks

- **A consumer who pins Omarchy with `follows` to the very commit nixarchy
  pins** gets the normal label. That is correct, because it is that commit.
- **The lock format:** `nodes.root.inputs.omarchy` is a node name today. If
  it ever became a follows path (a list), `or null` gives a null pin, and
  everything reads `dev-…`. The wiring assertion would catch that in CI, so
  it cannot ship silently.

## Verification

- §1:
  - break the function to always return `version`: the second case's
    assertion fires;
  - break the wiring (pass `pinnedRev = null`): the wiring assertion fires.
- **Real override, locally:**
  `nix eval --raw .#omarchy.version --override-input omarchy git+file:///<a quattro checkout with one extra commit>`
  prints `dev-<date>-<thatrev>`; without the override it prints `4.0.5`.
- A trial merge into `edge-candidate` is conflict-free. There, `.#omarchy.version`
  evaluates to `edge-20261019-81fd2d2` unchanged, and the check passes.
- `nix fmt -- --ci`.

Three files (the function, `flake.nix`, the check), so the `coder` agent
implements the plan.
