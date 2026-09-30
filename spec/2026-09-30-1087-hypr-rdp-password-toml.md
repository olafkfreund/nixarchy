---
status: approved
issue: 1087
intent: intent/2026-09-30-1087-hypr-rdp-password-toml.md
---

# Spec: Encode hypr-rdp credentials before the daemon reads TOML

## Design

`modules/services/hypr-rdp.nix:400-423` currently asks sops-nix to substitute a raw secret inside a TOML string. Instead, use its protected, user-owned `0400` template as a **raw password staging file**: its store source contains only the sops placeholder, never cleartext. Build the nonsecret TOML lines from `bind`, `username`, optional `output`, `certFile`, and `keyFile` with `builtins.toJSON` at evaluation. Confirm that the chosen JSON string representation parses as a TOML basic string with the same value, including quotes, backslashes, and control escapes. Keep the option values out of shell interpolation.

Extend the `ExecStartPre` guard at `modules/services/hypr-rdp.nix:118-149` to read that staging file at runtime. Refuse missing or empty input and any control byte, including newline, with a clear error that never prints the password. Escape literal backslashes and double quotes with one `sed` expression, then write the complete TOML to a private file under the user service's runtime directory. Use a `0700` directory, `umask 077`, a temporary file, `0400` final permissions, and an atomic rename so a failed render leaves no partial usable config. The final file stays outside the Nix store, is readable only by the service user, and is created before `hypr-rdp` starts. The guard validates the final file's username and password as nonempty and refuses any render failure; it never starts the daemon with an absent or empty credential. `ExecStart` at `modules/services/hypr-rdp.nix:453-467` points `--config` to this private final file. The explicit path continues to make a missing file a startup error.

Update the password option text at `modules/services/hypr-rdp.nix:208-227` and the user guidance at `docs/manual/remote-desktop.md:99-102`: quotes and backslashes are now supported literally, while control characters are refused. Keep the existing ownership, `ConditionUser`, and no-command-line-secret properties (`modules/services/hypr-rdp.nix:440-467`).

The existing `tests/options.nix:3077-3134` checks the old quoted placeholder and invokes the old guard; it must be adapted to the raw staging file, new guard arguments, and private final file. That file is reserved by the criticals PR and must not be edited until its owner releases it. A separate cheap check can cover the new behavior before then, but the old check must be updated before a PR is ready.

## Alternatives rejected

- Escaping the password during Nix evaluation: the cleartext exists only when sops-nix substitutes the placeholder at activation, so evaluation cannot see it safely.
- Keeping a raw password inside quoted TOML and relying on the parser: quote and backslash sequences can invalidate the file or silently change the credential; the present guard checks line shape, not the parsed value.
- Rejecting quotes and backslashes: the owner chose to support them through runtime escaping. Control characters are explicitly refused instead.
- Passing the password on the command line: `/proc/*/cmdline` would expose it; the existing file boundary is deliberate (`modules/services/hypr-rdp.nix:375-381`).

## Risks

- A rendering failure must not fall through to hypr-rdp's unauthenticated defaults. Keep the existing refusal and prove it with missing, empty, and control-character fixtures.
- The guard creates a second runtime copy of the secret. Both staging and final files must be user-owned and private; failed renders must not leave a partial final config that `ExecStart` can read.
- JSON and TOML string escaping are similar but not assumed identical. Parser-based fixtures must prove the chosen encoding for nonsecret fields.
- Changing the template shape invalidates the existing `checks.options` fixture until `tests/options.nix` is updated after the criticals file restriction lifts. Do not run that high-memory check locally.

## Verification

- Add a cheap `checks.hypr-rdp-toml` wired through `flake.nix` to take the built guard, template, and service command from an evaluated module, then run that guard against substituted staging-file fixtures. Parse the **final rendered TOML** with Python's `tomllib`, and assert parsed `password`, `username`, `bind`, `output`, `cert`, and `key` equal the original fixture values containing quotes and backslashes. Assert only a placeholder, never plaintext, occurs in the store template.
- Check missing, empty, newline, tab, carriage-return, and other control-byte passwords refuse before the daemon is started; the output contains an actionable error and no secret. Check the final config's mode and its absence after a failed first render.
- Update `tests/options.nix` when available, retaining its enabled/disabled assertions and its direct guard refusal cases. Run only cheap checks locally; let CI run `checks.options`.
- Prove the new check can fail: copy the edited module aside with `cp`, remove the runtime `sed` escape, run the cheap check and capture the parser or value-mismatch failure; restore with `cp` (never `git checkout`) and show it passes. Repeat by removing the control-byte refusal and expecting the corresponding fixture to fail. Include both red outputs in the PR.
