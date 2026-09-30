---
status: draft
issue: 1098
spec: spec/2026-09-30-1098-rdp-doc-leftovers.md
---

# Plan: Correct the remaining hypr-rdp release and password documentation

Refs #1098. This is a prose and comment correction. `flake.nix:127-129` and `flake.lock:231-250` pin hypr-rdp v0.1.6. The pinned `src/config.rs:478-520` supports `password_file` from TOML and CLI and rejects a missing or empty named file. `src/config.rs:279-289,301-361` still only warns for absent credentials or a username with an empty inline password; `src/server/mod.rs:200-206` turns absent credentials into no authentication. The current module uses sops-nix for a private password staging file and an `ExecStartPre` guard to write final `0400` TOML at service start (`modules/services/hypr-rdp.nix:103-149,375-399,428-467`). Keep that runtime design and its evaluation/runtime refusals. Retain v0.1.5 only as clearly dated #154 history. Migration to upstream `password_file` is separate work. No host, unit, secret, or test-assertion behavior changes.

The owner explicitly directed local implementation after this draft is committed. This does not approve the plan: `status: draft` remains until an explicit plan approval, and no approval commit is implied.

## Steps

1. `modules/secrets.md:40-61`: mark the v0.1.5 two-source limit and original sops-nix choice as history; state pinned v0.1.6's `password_file` support and named-file failure; describe today's staging file, service-start private TOML and continuing guard; avoid saying agenix or `password_file` is inherently unsuitable now -> verify by reading the pinned source and `bash tests/rdp-docs.sh .`. Trap: retain both fail-open cases.
2. `docs/internals/flake.md:229-235,272-288`: replace the current-release claim with v0.1.6; distinguish the original decision from the current password sources and runtime flow while preserving the tagged-input rationale -> verify by `bash tests/rdp-docs.sh .`. Trap: this file explains historical design, so historical v0.1.5 may remain only when dated.
3. `docs/manual/remote-desktop.md:53-69`: explain the two warning-only cases, missing/empty named-file refusal, sops password staging and service-start guard; retain command-line/store exposure warnings and the evaluation assertion -> verify by `bash tests/rdp-docs.sh .` and manual read-through. Trap: no cleartext in Nix evaluation, git or process arguments.
4. `tests/options.nix:2266-2272,2300-2309`: update only the old source/version comments and the historical sops-nix rationale, naming both warning-only cases and current `src/config.rs:279-289,301-361,478-520` and `src/server/mod.rs:200-206`; leave assertions and fixtures unchanged -> verify by `git diff` plus `bash tests/rdp-docs.sh .`. Trap: after this `.nix` edit run `nix fmt`, inspect `git diff --stat`, then `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .`, and `nix run nixpkgs#deadnix -- --fail .`.
5. `tests/rdp-docs.sh` and `tests/doc-options.nix:87-90`: add direct-file assertions of the current release, file support, two warning-only cases, and staging/service-start flow; invoke them inside the existing CI-wired `checks.doc-options` instead of creating an unwired check -> verify by `bash tests/rdp-docs.sh .` and `nix build .#checks.x86_64-linux.doc-options` under the shared lock. Trap: use direct file reads; no producer piped into `grep -q`. A build requires `gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'` to print 0 unless the owner cheap-check waiver applies; `doc-options` is listed as cheap in `tests/AGENTS.md` and the waiver applies. Never run VM or `checks.options` locally.

## Tests

- First add the static check against the *old* four files. Run `bash tests/rdp-docs.sh .` and capture a named red failure. Then make Steps 1-4 and show it green. This proves the check sees the real stale claims.
- For a second break proof, copy one corrected file to `/mnt/data/vmtest/1098-rdp-doc-good`, reintroduce its old wording, run the check and capture its named red line, restore the file with `cp`, and show green. Never use `git checkout` for break proofs. Remove the saved copy afterward.
- Run the existing `checks.doc-options` under `flock /mnt/data/vmtest/codex-build.lock` (one build at a time). Check CI load first unless the owner cheap-check waiver applies. Its green output proves the new assertions are in a CI-wired check. Do not run VM or `checks.options` locally.
- Confirm the source and module facts by direct read. Run `git diff --check` and, after `.nix` edits, formatting and lint gates from Step 4. Scan the diff for `| grep -q` and writes to `omarchy/shell.json`.

## Rollback

Revert the implementation commits for Steps 1-5. The runtime module and secrets were never changed; removing the new `doc-options` invocation and restoring the previous prose returns to the prior documentation state.
