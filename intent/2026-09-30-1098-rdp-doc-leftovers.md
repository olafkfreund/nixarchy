---
status: draft
issue: 1098
author: olafkfreund
---

# Intent: Correct the remaining hypr-rdp release and password documentation

## Problem

Refs #1098. The earlier stale-docs change corrected `modules/services/hypr-rdp.nix`, but four other references still describe the old release as current. The claims hold up against `flake.lock:231-250`, which pins v0.1.6 at `8744778`, and that pinned source's `src/config.rs:478-520`, which accepts `password_file` from the CLI or TOML and rejects a missing or empty named file:

- `modules/secrets.md:40-53` and `docs/internals/flake.md:272-283` say there is no `password_file`, that only an inline password or CLI flag is possible, and that the secret must be rendered inside TOML. These were true of v0.1.5 when sops-nix was adopted, but are false as present-tense descriptions of v0.1.6. The flake note at `docs/internals/flake.md:229` also calls v0.1.5 the version this project takes on.
- `docs/manual/remote-desktop.md:53-68` and `tests/options.nix:2266-2270,2300-2307` still name v0.1.5 and its old source lines, and repeat the two-source claim. The manual also says sops-nix renders the full config at activation; the current guard in `modules/services/hypr-rdp.nix:103-149,428-467` renders private TOML at service start from a password staging file.

The fail-open warning itself remains valid: in pinned `src/config.rs:301-361`, no credentials produce warnings rather than an error, and a username with an empty inline password receives only a `HalfCredentials` warning. The module's runtime refusal still matters. This is a documentation mismatch, not evidence that the current guard should be removed.

## Proposed outcome

The contributor notes, flake internals, remote-desktop manual and option-check comments distinguish the original v0.1.5 rationale from current v0.1.6 behavior. They describe the current sops staging file and service-start rendering accurately, preserve the no-credentials and empty-inline-password safety rationale, and cite current source lines where they cite lines at all.

## Affected users and systems

Maintainers and reviewers reading `modules/secrets.md`, `docs/internals/flake.md` and `tests/options.nix`; users following `docs/manual/remote-desktop.md`. Documentation and comments only; no change to the RDP unit, secrets, configuration, or host behavior.

## Constraints

- Refs #1098; this is the hypr-rdp documentation leftover from the stale-docs group, not a new implementation of upstream `password_file`.
- Keep the existing fail-closed module guard and current runtime secret boundary. Do not put cleartext in the Nix store, command line, or git.
- Verify wording against the locked v0.1.6 source and the actual module. If a documentation assertion is added, prove it fails on the stale wording before accepting a green run. Do not run Nix builds at this gate.
- Work stays local in this issue's worktree until the orchestrator releases the push hold.

## Open questions

1. Should the original v0.1.5 explanation be retained as explicitly dated history? **Recommendation:** yes, briefly, because it explains why sops-nix and TOML templating were chosen in #154; immediately distinguish the pinned v0.1.6 behavior and today's runtime guard.
2. Should this documentation cleanup also migrate the module to upstream `password_file`? **Recommendation:** no. The previous #1098 stale-docs decision deferred that runtime change, which would need its own design and tests.
