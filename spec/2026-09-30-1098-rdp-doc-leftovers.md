---
status: draft
issue: 1098
intent: intent/2026-09-30-1098-rdp-doc-leftovers.md
---

# Spec: Correct the remaining hypr-rdp release and password documentation

Refs #1098. The change is documentation and comments only. `flake.nix:127-129` and `flake.lock:231-250` pin v0.1.6 at `8744778de2eb9add74224d57fac399aba6039a26`; its `src/config.rs:478-520` accepts CLI and TOML `password_file` and rejects a missing or empty named file. Its `src/config.rs:279-289,301-361` still permits absent credentials and warns, rather than failing, for a username with an empty inline password. No startup guard may be removed on the strength of the new option.

## Design

1. `modules/secrets.md:40-61`: label the v0.1.5 two-source limitation as the historical reason for choosing sops-nix in #154. Immediately describe the pinned v0.1.6 `password_file` option and its named-file failure behavior. Replace the present-tense claim that TOML interpolation is required with the current design: sops-nix writes a private raw-password staging file and the module's guard composes private TOML at service start (`modules/services/hypr-rdp.nix:103-149,375-399,428-467`). Retain the security reason for that guard: absent credentials and an empty inline password do not stop upstream (`src/config.rs:301-361`). Do not imply agenix or `password_file` is inherently unsuitable today; explain why the existing design was chosen then and is retained now.
2. `docs/internals/flake.md:229-235,272-288`: update the current pinned release to v0.1.6. Treat the v0.1.5 password-source limitation as dated history, then state the current option and actual sops staging/guard flow. Keep the reasons for a tagged flake input and for choosing sops-nix historically, without claiming the raw secret must still be interpolated by sops at activation.
3. `docs/manual/remote-desktop.md:53-69`: cite current v0.1.6 behavior: a missing or empty **named** password file fails, while no credentials and username plus empty inline password only warn (`src/config.rs:301-361,478-520`). Explain the actual user's flow: sops-nix renders a `0400` password staging file, then `ExecStartPre` reads it and atomically writes the `0400` runtime TOML before the service starts (`modules/services/hypr-rdp.nix:103-149,375-399,428-467`). Keep the warning about command-line and store exposure. The module still asserts at evaluation and refuses at runtime.
4. `tests/options.nix:2266-2272,2300-2309`: update only comments. Attribute the original sops-nix choice to the v0.1.5 limitation rather than saying the pinned daemon has only two password sources. Replace the obsolete `src/config.rs:187-197` and `src/server/mod.rs:123` citation with the pinned v0.1.6 `src/config.rs:279-289,301-361,478-520` and `src/server/mod.rs:200-206` flow. State both fail-open cases. Leave the assertions and fixtures unchanged.

## Alternatives rejected

- Switch the unit to upstream `password_file`: the owner deferred that runtime change; it needs its own design and checks. This task corrects what the existing service does.
- Remove the runtime guard because a named password file now fails closed: no credentials still start unauthenticated, and an empty inline password still produces only a warning.
- Erase all v0.1.5 context: it explains #154's original sops-nix decision. Keep it only when clearly marked as historical, next to the current v0.1.6 facts.

## Risks

- A prose edit could imply v0.1.6 refuses every empty-credential state. Distinguish a missing/empty **named file** from absent credentials and empty **inline** password in each explanation.
- `docs/manual/remote-desktop.md` is user-facing. Wording must describe the existing private paths and timing accurately, without inviting a plaintext secret into Nix evaluation, git, or process arguments.
- `tests/options.nix` comments sit beside security assertions. Keep test logic byte-for-byte unchanged; after a `.nix` edit, run `nix fmt`, inspect `git diff --stat`, and run the repository's formatting and lint gates at implementation time.

## Verification

- Read the locked upstream source at `src/config.rs:279-289,301-361,478-520` and `src/server/mod.rs:200-206`, and compare it to the four edited files and `modules/services/hypr-rdp.nix:103-149,375-399,428-467`. No Nix build is needed for this documentation gate.
- Use a small direct-file shell assertion for the documentation claims. It must require current `v0.1.6` and `password_file` facts, both remaining warning-only cases, and the staging-file/service-start flow; reject present-tense claims that there is no `password_file`, that only two password sources exist, or that sops-nix writes final TOML at activation. Match each target file separately, not by searching the whole tree, and do not use a producer piped into `grep -q`.
- Prove the assertion red **before** editing: run it on the present stale files and capture its named failure. After editing, copy one corrected file aside outside the worktree, reintroduce the obsolete claim in that file, verify red again, restore with `cp` (never `git checkout`), and verify green. Capture the red and green lines for the eventual PR. Confirm `git diff` contains only the intended prose/comments.
