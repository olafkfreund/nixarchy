---
status: draft
issue: 783
intent: intent/2026-09-19-783-plugin-layout-wait.md
---

# Spec: Wait for the default plugin's persisted bar placement

## Design

Keep the enabled-IPC wait in the defaults node of `tests/plugin.nix`. Add
one bounded `machine.wait_until_succeeds` immediately before its existing
`shell.json` read. The command reads
`/home/omarchy/.config/omarchy/shell.json` with `${pkgs.jq}/bin/jq -e`, uses
`--arg id` for the existing `tele` id, and succeeds only when
`any(.bar.layout.right[]?; .id == $id)` is true. Use a 60-second timeout.
Missing files, invalid JSON, absent layout sections and an absent id return
nonzero and remain unsuccessful until the timeout or a correct write.
The `-e` flag is required: plain jq exits zero even when its result is false,
which would make the wait accept the stale layout immediately.

Retain the subsequent Python layout assertion and its diagnostic, the
enable-once marker check, and the disable/re-login check. The added wait
observes the persisted condition those assertions need. It neither changes
plugin enablement nor introduces another configuration writer.

The source of the ordering is the shell's `persistShellConfig`: it assigns
the in-memory configuration before calling `userConfigFile.setText`, while
the enable IPC returns without waiting for persistence. Waiting for enabled
alone therefore does not establish that a disk read sees the new layout.

The implementation stays in the existing defaults-node test block, with a
short explanation of the IPC/disk distinction. Reuse jq already in the
dependency graph and the NixOS driver's existing retry implementation.
No new flake check, workflow, package dependency or production change.

Current main is `bf4c64cb1743105e7867a52422b96e67e7196b8d`.
Claude's #780 and stacked #782 change the machine-node setup near line 147
to disable the real package plugin in this fixture. They do not change the
defaults-node assertion near line 589. Preserve their changes on rebase and
rerun the relevant integration check against the resulting base.

## Alternatives rejected

- A fixed sleep assumes how quickly the write finishes and leaves the same
  race on a slower runner.
- Reading layout through IPC verifies memory, losing the current assertion
  that the configuration was actually persisted.
- Retrying the full VM check until green conceals the defect and wastes a
  complete test run for a local synchronization problem.
- Changing shell persistence or the enable hook expands this test fix into
  production behavior that the issue does not require.

## Risks

The eventual condition could be wrong or permanently absent; a bounded
wait must fail in those cases, rather than accepting any nonempty layout.
Use the exact plugin id and right section. The existing detailed assertion
remains useful after success; jq's stderr and driver retry output provide
evidence when the file cannot be read or parsed.

An isolated delayed-file replay proves the read/wait behavior, not the
shell's complete runtime. The real `checks.plugin` run remains required.
VM builds must wait until the CI install queue permits local work under
AGENTS.md section 6; a pending check is reported as pending, never passed.

## Verification

1. Prepare a temporary, uncommitted replay under `/mnt/data/vmtest/` using
   the old layout-read/assert block and the corrected block from this file's
   target test. Use the actual jq predicate from the corrected test, not a
   separately reimplemented membership condition. Redirect only the fixture
   file path; never write the desktop's real configuration.
2. Start with valid JSON whose right section lacks `tele`, and represent
   the enabled IPC prerequisite as already satisfied. A controlled producer
   atomically replaces that file with correct JSON only after the reader has
   observed the old contents. Use an explicit reader/producer handshake,
   rather than hoping a timed sleep hits the race window. Run both versions
   with that ordering: capture the old assertion failing and the new wait
   observing a failed attempt followed by success. Release and join the
   producer even when the old assertion raises.
3. Run the corrected predicate/wait with no producer update, and separately
   with the id only under `bar.layout.left`. Both must exhaust a short
   replay timeout and fail. Assert the jq command's nonzero exit status in
   both cases, not merely its printed `false`; removing `-e` must fail this
   verification. An already-correct right section must exit zero and pass
   immediately. These negative cases prevent a wait that merely sees valid
   JSON or an enabled plugin from counting as success.
4. Record that this replay controls delayed persistence; it does not claim
   to run QML. When capacity permits, run the existing
   `nix build .#checks.x86_64-linux.plugin --print-build-logs` from the
   committed worktree, without piping away its exit status. It must pass
   with the unchanged marker and disable-persistence assertions exercised.
5. Run the repository formatting check and `git diff --check`. Include the
   captured old failure, new success, negative-case failures and integration
   result in the PR. Remove temporary replay assets from the final diff;
   the runnable regression check remains in `tests/plugin.nix`.
