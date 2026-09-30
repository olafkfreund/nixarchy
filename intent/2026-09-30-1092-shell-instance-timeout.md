---
status: draft
issue: 1092
author: olafkfreund
---

# Intent: bound the shell-instance probe

## Problem

The #963 path-first fallback probes a Quickshell instance before every `omarchy-shell` IPC call. The probe at `pkgs/omarchy/default.nix:2037` has no timeout, although the real call at `:2062` uses the existing `$ipc_timeout` (two seconds by default). A stalled shell can therefore hold an `omarchy-shell` caller before it reaches the bounded call. The issue's timeout claim holds; “every keybind” is broader than the code proves, because this affects keybinds and commands that call `omarchy-shell`.

The issue's documentation claim also holds. `pkgs/AGENTS.md:208-210` says `Target not found.` makes `qs ipc` exit 1, while the upstream wrapper's own comment and `tests/session.nix:713-716` say raw `qs ipc` emits IPC-level errors on stdout with exit 0. The wrapper later translates that reply into a failure for its callers. The distinction matters to the probe, which inspects raw `qs` status.

## Proposed outcome

The instance probe ends within the existing IPC timeout plus the short kill grace period, and the package documentation describes raw `qs` status accurately. A check makes the unbounded-probe regression fail.

## Affected users and systems

Nixarchy desktop users whose keybinds, panels, or scripts call `omarchy-shell`, particularly while Quickshell is stalled. The vendored Omarchy package patch and its `shell-ipc-resolve` check are affected; no host-specific configuration is involved.

## Constraints

- Preserve #963's path-first instance selection and refusal to guess among multiple running shells.
- Reuse the wrapper's existing configurable `$ipc_timeout` and `timeout --kill-after=1s` convention; avoid a second timeout setting.
- Prove any new check fails with the bound removed, then passes with it restored. Use a stub that can hang and record the observed exit or duration, not a source-text assertion alone.
- This is an intent gate only: no implementation edits or Nix builds yet. Do not edit installer, microVM, or `tests/options.nix` files reserved for another PR.

## Open questions

- Should `qs list --all`, which runs only after a failed probe, also receive a deadline? **Recommendation:** keep this issue focused on the reported blocking probe; add a listing deadline only if a separate hang is demonstrated or the spec's verification shows it can block.
- Should the probe use a new duration? **Recommendation:** no; use the existing `OMARCHY_SHELL_IPC_TIMEOUT` value (default two seconds), matching the real call.
