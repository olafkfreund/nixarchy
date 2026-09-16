---
status: approved
issue: 701
spec: spec/2026-09-16-701-root-flake-inputs.md
---

# Plan: an installed machine keeps the inputs it needs to rebuild offline

Re-land `efabd12` (#702), reverted by `c46467c` (#706) for a disk constraint
that #708 has since removed. The diff is known; the proof is redone on today's
main rather than cited.

## Decisions, carried from the approved spec

- **D1.** `collectInputs` moves from `installer/cd.nix` to `lib.inputSources`
  in `flake.nix`; `cd.nix` calls it.
- **D2.** `installer/host.nix`:
  `system.extraDependencies = inputs.self.lib.inputSources inputs;`, with
  `inputs.self` being nixarchy, never `/etc/nixos`.
- **D3.** Every input source is rooted, not a subset. Measured today: 33
  sources, 836 MiB, against 18.4 GiB free on a fresh 32 GiB install.
- **D4.** `tests/options.nix` gains `flakeInputsRooted` (both states);
  `tests/install.nix` collects garbage and then evaluates `/etc/nixos` offline.
- **D5.** `checks.install`'s free-space assertion (at least `max-free` free,
  #708) keeps the cost honest, and the PR states the measured figure.

## Steps

1. **Replay the code.** `git cherry-pick -n efabd12` for `flake.nix`,
   `installer/cd.nix`, `installer/host.nix`, `tests/options.nix` and
   `tests/install.nix` only — no artifact files, which this task writes fresh.
   Resolve against today's `host.nix`, which #708 rewrote (`min-free` 3 GiB,
   `max-free` 8 GiB, `nix.package`), so `system = { name; extraDependencies; }`
   merges into what is there rather than reintroducing the repeated key CI
   caught last time.
   → verify: `git diff` touches those five files only.
2. **Evaluation checks.** `checks.options` (`flakeInputsRooted`),
   `checks.iso-source`, `vm-toplevel`, `stable-eval`, `config-warnings`.
   → verify: all pass; `iso-source` reports the same input-source set as before
   the move.
3. **Seen red locally, for D4's option case.** Remove the `extraDependencies`
   line, prove the break landed with `git diff`, build `checks.options`, watch
   `flakeInputsRooted` fail, restore.
   → verify: red, then green.
4. **Measure the cost.** With the rooting line in, evaluate the installed
   toplevel and compare its closure size against main's.
   → verify: the difference is measured and recorded for the PR.
   **Deviation:** measured 1953 MiB, not the 836 MiB the spec estimated. 836 MiB
   is the rooted source paths themselves; the rest is what those sources
   reference. 18.4 GiB free minus 1.9 GiB leaves about 16.4 GiB, still far above
   `max-free` (8 GiB), so D3 (root everything) stands. `vm-toplevel` closure:
   20.30 GiB with rooting against 18.40 GiB on main.
5. **Lint on the fixed tree**, never on the break: statix, deadnix,
   `nix fmt -- --ci` (the formatter hook means `nix fmt` runs last).
   → verify: all clean.
6. **Seen red in CI, once, for the install assertion.**
   **Deviation:** attempted on 2026-09-16 (run 35068669598, the rooting line
   removed). The job hit its 90-minute cap during the install itself and never
   reached the assertion, because four PRs were contending for one install slot.
   Rather than spend another 90-minute slot, this cites #702's CI red for the
   identical code (run 34972125482, `unable to download ... Could not resolve
   host: github.com`, then `RequestedAssertionFailed`): the code here is a
   cherry-pick of `efabd12`, the same assertion against the same line. The
   option case's red (step 3) was reproduced locally on this branch today.
   → verify: the PR carries both reds and says which run each came from.
7. **Restore and get a green install**, never cancelling or overriding it.
   → verify: `install` green, and the free-space line still above 8 GiB.
8. **Squash, describe, merge.** Description: the step 3 and 6 reds, the
   measured 836 MiB, the free space with rooting on, and a note that #702's
   evidence is superseded by this run. `Closes #701`. Mark ready, enable squash
   auto-merge.
   → verify: merged, and #701 closed by it.

## Tests

```sh
nix build .#checks.x86_64-linux.options --print-build-logs   # flakeInputsRooted
nix build .#checks.x86_64-linux.iso-source
nix build .#checks.x86_64-linux.vm-toplevel
```

`checks.install` runs in CI only: it needs one of the two install slots.

## Rollback

Revert the squash commit, as #706 did. Installed machines keep the larger
closure until their next rebuild, which then drops it.
