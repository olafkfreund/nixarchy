---
status: draft
issue: 1274
intent: intent/2026-10-15-1274-review-findings.md
---

# Spec: fix the findings from the 2026-10-15 three-model code review

Numbers match the intent.

## Design

### Installer (`installer/install.sh`, `installer/try.sh`)

1. **Boot medium, unattended.** In `validate_answers`'s device block, after
   the whole-disk test, refuse `readlink -f "$device"` when it equals
   `readlink -f "$(boot_medium)"`. This is the same predicate
   `confirm_repo_disks` already uses (`:1593-1601`), so there are now three
   callers of `boot_medium` and no second spelling of the test.
2. **Retry after a successful install.** The chain sets a flag
   (`installed=true`) as soon as `run_install` returns 0. `install_attempts`
   keeps it across iterations. When it is set, `install_once` skips
   `format_disk … run_install` and runs only the phases after it
   (`chown_flake_dir`, `carry_network_profiles`, `take_factory_snapshot`).
   Each of those must tolerate a second run; where one does not (an
   existing snapshot, say), it is made to. The flag is in memory, like the
   answers. Nothing on disk records it.
3. **Recovery passphrase reuse.** `read_answers` compares plaintext before
   hashing, as the interactive path does. If `password` and
   `recovery_passphrase` are both given, equal is refused. For a mixed pair
   (a plaintext beside the other's hash), the plaintext is re-hashed with the
   hash's own salt (`mkpasswd -m sha-512 -S <salt>`) and compared. This only
   works for `$6$` without `rounds=`. Other formats keep today's equality
   test, marked with a `shortcut:` comment. The plaintext still never
   reaches argv: `mkpasswd -s` reads stdin.
4. **`write_password_hash`.** Each step is chained with `|| return 1`: both
   subshells, `chmod` and `chown`. The function returns 0 only when every
   write landed.
5. **`--from` on a free-space host.** In `confirm_repo_disks`, a `dev` that
   `lsblk` calls `part` is mapped to its parent (`lsblk -no PKNAME`).
   Parents are deduplicated, since the ESP and root share one, and
   `remember_disk` gets the parent. The boot-medium test then runs against
   the parent too.
6. **`--from` hash format.** The `from_host_exists` branch of
   `validate_answers` gets the same `'$'*` case the normal branch has.
7. **Partial free-space partitioning.** The two `sgdisk --new` calls become
   one. Measured 2026-10-15 on a 200 MiB image with gptfdisk: when the
   second `--new` fails, sgdisk prints "Error encountered; not saving
   changes", exits 4 and leaves the table untouched. So a half-made layout
   cannot exist, and no cleanup code is needed.
8. **`try.sh`.** Drop the EXIT trap. `rm -f "$dry"` right after
   `classify_plan` reads it, and in the dry-run failure branch before its
   `exit 1`.

### Modules

9. **`services/open-webui.nix`.** `environment` stays a plain attrset, and
   each value inside it is wrapped in `lib.mkDefault`. Keys still merge
   with a user's own. A user's value for the same key now wins rather than
   conflicting.
10. **`fleet.nix`.**
    - `system.autoUpgrade.{enable,flake,dates,randomizedDelaySec}` get
      `lib.mkDefault`. `flags` is a list and stays plain.
    - `url` gets `default = ""`, so a missing URL reaches the existing
      assertion instead of nix's "used but not defined".
    - The failure script uses `${lib.escapeShellArg cfg.url}`.
11. **`auto-update.nix`.** `[ -d "$flake/.git" ]` becomes
    `[ -e "$flake/.git" ]`. A worktree's `.git` is a file, and
    `git -C` handles both.
12. **`services/tailscale.nix`.** `trustedInterfaces = [
    config.services.tailscale.interfaceName ]`.
13. **`services/microvm.nix`: documented, not changed.** The line exists
    because nixarchy imports `microvm.nixosModules.host` into every
    configuration, and upstream's default (`true`) would otherwise give every
    importer a microvm host, user and kernel modules. The module system
    cannot tell "the user imported it as well" from "only nixarchy did". The
    escape is the user's own plain `microvm.host.enable = true;`, which
    outranks our `mkDefault`. That sentence goes in the option description
    and in `modules/AGENTS.md` under the existing microvm entry.

### Agent bus

14. **`bus-redact.sh`.** When the post names no room, `room` is
    `${AGENT_BUS_ROOM:-}`, and empty stays empty. Only the literal `#agents`
    takes the relaxed set, so an unknown room gets the strict rules, as the
    header already promises. `tests/bus-redact.nix:85`, which asserts the old
    "no room, no env → #agents rules", is **retargeted** to `block`. It
    measured the arrangement (mirror the server default) and not the
    property (never relax without knowing the room). The PR says so.
15. **`agent_bus_mcp.py`.** With no cursor, `read_new` and `peek` call
    `/messages` with `dir=b` and the same `limit`. They reverse the chunk
    into chronological order and store the response's `start` token, which
    is the timeline's live end, as the cursor. With a cursor, nothing
    changes (`dir=f`, `from=cursor`, store `end`). Docstrings stay as they
    are, because they now describe the code.

## Alternatives rejected

- **#2: resume from the exact failed phase via a phase index.** It is more
  general, but only the post-install boundary is unsafe to repeat. Every
  phase before `run_install` is already re-run by design (#1084).
- **#2: offer no retry after a successful install.** That leaves a person
  with a bootable disk and no way to finish the snapshot except a shell.
- **#3: verify with perl's `crypt()`.** It handles every format, but perl
  is not declared to this script, and §7 says an undeclared command reads
  as a wrong answer.
- **#7: delete the ESP entry on failure.** The partition number has to be
  found, and in free-space mode this deletes on a disk holding another OS.
  An atomic call needs neither.
- **#13: gate the line on `cfg.enable`.** That gives every Mode A importer
  an unrequested microvm host, which is the larger Mode A break.
- **#14: read the room from the MCP server's environment.** A hook cannot
  see another process's environment.
- **#15: `/sync` with a filter for the first read.** Another code path and
  token format for a one-call difference.

## Coexistence (§14)

Fixes 9, 10 and 12 are coexistence fixes: a user's own value meets ours. They
are not fixtures in `tests/coexistence/fixtures.nix`, because those carry no
`programs.nixarchy.*`, and each conflict needs nixarchy's service on. They
are asserted in `tests/options.nix`, which builds exactly that machine:
the service on, plus the user's own `OLLAMA_API_BASE_URL`,
`system.autoUpgrade.randomizedDelaySec` and `services.tailscale.interfaceName`
all evaluate, and the user's value wins. Fix 13 is the same class, answered
by documentation, with the reason in the alternatives.

## Risks

- #2: a post-install phase that is not idempotent fails its second run. It
  fails loudly, and that is caught by the new retry check.
- #3: a `$6$rounds=` or yescrypt hash skips the re-hash. Same as today, and
  marked with a `shortcut:` comment.
- #9 and #10: a user who relied on the conflict error to spot a typo loses
  it. Their value now wins, which is the documented rule.
- #14: a maintainer posting a private IP to `#agents` without naming the
  room is now blocked. That is the strict direction, and naming the room
  lifts it.
- #15: a homeserver that omits `start` on `dir=b`. The code then keeps no
  cursor, and the next call repeats the newest page. That is not a loss.
- No host deploy. Nothing here is switched on any machine by the PR.

## Verification

Each fix gets one case in an existing cheap check. Each is shown failing with
the fix reverted, then passing (§1). The failing output goes in the PR.

| fix | check | how |
|---|---|---|
| 1, 3, 6 | `installer-answers` | extract `read_answers`/`validate_answers`, stub `boot_medium`/`lsblk`/`mkpasswd` |
| 2, 4 | `installer-answers`, or a new `installer-retry` runCommand if extraction does not fit | stub the phases; a failure after `run_install` must not call `format_disk` on retry; a failing write must make the phase fail |
| 5, 7 | `installer-from-repo` (5); a gptfdisk image run inside the check (7) | partlabel devices map to one parent; a failing second `--new` leaves no partition |
| 8 | `try-preflight` | no `nixarchy-try` temp file left after a successful dry-run classify |
| 9, 10, 11, 12 | `options` (CI), proved locally by targeted `nix eval` of the new cases | user values win; `url` unset reaches the assertion message; `-e` in the script |
| 13 | none | documentation only |
| 14 | `bus-redact` | retargeted case blocks |
| 15 | `bus-mcp` | an httpx `MockTransport` homeserver: the first `read_new` sends `dir=b`, returns the newest in order, and the second sends `dir=f` from `start` |

Static checks too: `nix fmt -- --ci`, statix and deadnix. VM checks (`install`,
`free-space`, `installer-refusal`) run in CI on the PR.
