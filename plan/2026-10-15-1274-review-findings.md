---
status: approved
issue: 1274
spec: spec/2026-10-15-1274-review-findings.md
---

# Plan: fix the findings from the 2026-10-15 three-model code review

Self-contained. Worktree `/mnt/data/vmtest/wt-1274`, branch
`fix/1274-review-findings`, based on `0569953b`. One PR. Owners, as the owner
asked: **Codex** steps 1–3 (installer), **agy** step 4 (modules), **Claude**
steps 5–7 (bus, try.sh, review, proofs and PR). Codex and agy do not commit;
Claude reviews each diff, runs its check and commits.

## Approved decisions

- Boot medium: `validate_answers` refuses `readlink -f device` equal to
  `readlink -f "$(boot_medium)"`, the predicate `confirm_repo_disks` uses.
- Retry: an in-memory `installed=true` is set when `run_install` returns 0.
  When it is set, a retry runs only `chown_flake_dir && carry_network_profiles
  && take_factory_snapshot`. Each must survive a second run.
  *Found in step 2:* none needed a change. `carry_network_profiles` and
  `take_factory_snapshot` always return 0, so only `chown_flake_dir`, an
  idempotent chown, can send a person to the retry, and it fails before the
  snapshot exists. The check's stub fails `chown_flake_dir` once for that
  reason.
- Recovery reuse: compare plaintext in `read_answers` before hashing. For a
  mixed plaintext and `$6$` hash, re-hash with the hash's salt via
  `mkpasswd -m sha-512 -S <salt> -s` (stdin, never argv). Other formats get a
  `shortcut:` comment and keep the equality test.
  *Deviation (step 1):* `$6$rounds=N$` is re-derived too (`-R N`), since the
  repo's own hashes use it, and both directions share one top-level helper,
  `sha512_matches`. The check extracts it beside `read_answers`.
- `write_password_hash`: every write, chmod and chown `|| return 1`.
- `--from` free-space: a `part` maps to its parent through
  `lsblk -no PKNAME`. Deduplicate, then boot-medium test and `remember_disk`
  on the parent.
- `--from` hash: the same `'$'*` case in the `from_host_exists` branch.
- Free-space partitions: ONE `sgdisk` call creates both. Measured atomic:
  failure prints "Error encountered; not saving changes" and exits 4.
- `try.sh`: no EXIT trap. Explicit `rm -f "$dry"` after `classify_plan` and
  before the failure branch's `exit 1`.
- `open-webui`: `lib.mkDefault` on each `environment` value, attrset plain.
- `fleet`: `mkDefault` on `system.autoUpgrade.{enable,flake,dates,
  randomizedDelaySec}`, `flags` plain. `url` gets `default = ""`. The script
  uses `lib.escapeShellArg cfg.url`.
- `auto-update`: `[ -e "$flake/.git" ]`.
- `tailscale`: `trustedInterfaces = [ config.services.tailscale.interfaceName ]`.
- `microvm` (fix 13): **no edit.** The option description at
  `modules/services/microvm.nix:61-64` already tells imperative-only users to
  set `microvm.host.enable = true` themselves. The review could not see that.
- `bus-redact`: `[ -n "$room" ] || room="${AGENT_BUS_ROOM:-}"`, so an unknown
  room is strict. Retarget `tests/bus-redact.nix:85` to `block`.
- `agent_bus_mcp`: with no cursor, `dir=b`, reverse the chunk, store `start`.
  With a cursor, unchanged.

## Traps that apply to every step

- **A flake sees only tracked files.** A new file is invisible to
  `nix build` until `git add`. Codex and agy cannot stage, so prefer
  extending an existing check. If a new file is unavoidable, **report it**,
  and Claude stages it.
- **Cheap checks only, one at a time:**
  `flock /mnt/data/vmtest/codex-build.lock env -u NIXPKGS_ALLOW_UNFREE nix build --no-link .#checks.x86_64-linux.<name> -L`.
  Never a VM check, never `checks.options` (CI runs it).
- **No heredoc inside a `''…''` Nix string.** It reindents the file under
  nixfmt. Use `printf '%s\n'`.
- **A `.nix` edit may be reformatted by a hook.** Run `nix fmt` and read
  `git diff --stat`.
- **The extraction idiom.** Checks pull one function out with
  `sed -n '/^name()/,/^}/p'` and stub its commands. Keep any new function
  top-level with its closing `}` at column 0, or the extraction breaks
  silently.
- **§1.** Each new case must be seen failing with the fix reverted. Claude
  does the break-and-restore proofs in step 7, with `cp` aside, never
  `git checkout --`.
- Do not commit, push, deploy or restart anything.

## Steps

1. **Codex: answers validation (fixes 1, 3, 6).**
   - `installer/install.sh` `read_answers` (`:1264`, the
     `recovery_passphrase)` line `:1319`, the hashing block after the loop):
     keep the recovery plaintext until after `password` is hashed, refuse
     equal plaintexts, and handle the mixed `$6$` case as decided.
   - `validate_answers` (`:1348`): the device block after
     `"is not a whole disk"` (`:1386`) gets the boot-medium refusal. The
     `from_host_exists` branch gets the `'$'*` hash case. Keep the hash
     equality check at `:1442`.
   - Tests in `tests/installer-answers.nix`. It already extracts
     `read_answers` and stubs `mkpasswd`. Extract `validate_answers` the same
     way, stubbing `boot_medium`, `lsblk`, `disk_under_floor`,
     `free_space_possible`, `validate_hostname`, `validate_username`,
     `validate_timezone` and `validate_keymap`. Add three cases: device equal
     to the boot medium is refused; `password` equal to `recovery_passphrase`
     is refused; `--from` with `password_hash=oops` is refused.
   - → verify by building `installer-answers` (green).

2. **Codex: phases (fixes 2, 4).**
   - `write_password_hash` (`:2193`): `|| return 1` on every step, both
     halves.
   - `install_once` chain (`:3286-3295`) and `install_attempts` (`:3218`):
     `run_install && installed=true && chown_flake_dir && …`. Declare
     `installed=false` in `install_attempts` before the loop. In
     `install_once`, when `installed` is true, run only the three
     post-install phases.
   - Read `chown_flake_dir` (`:2293`), `carry_network_profiles` (`:2969`)
     and `take_factory_snapshot` (`:2987`) for a second-run failure, and
     make any that would fail tolerate it.
   - Tests: extend `tests/installer-answers.nix`, or, if it reads more
     clearly, add `tests/installer-retry.nix` plus its `checks` entry in
     `flake.nix` beside `installer-answers` (report both as new). Cases:
     - with `run_install` stubbed to succeed and `take_factory_snapshot` to
       fail once, the second attempt does not call `format_disk`;
     - `write_password_hash` against an unwritable target, with an empty
       `recovery_hash`, returns non-zero.
   - → verify by building the check.

3. **Codex: disks (fixes 5, 7).**
   - `confirm_repo_disks` (`:1579`, the loop ending at `remember_disk`
     `:1607`): map `part` to its parent, deduplicate, then test boot medium
     and `remember_disk` on the parent. The printed ERASE line names the
     parent disk.
   - Free-space partitioning (`:1704-1716`): one `sgdisk` call with both
     `--new`. Keep `check_disks` before it, one error message that says
     nothing was written, and `return 1`.
   - Tests:
     - fix 5: extend `tests/installer-from-repo.nix` (read how it stubs
       `lsblk`) with a case of two `by-partlabel` devices on one parent
       disk, which must reach `remember_disk` once with the parent;
     - fix 7: inside an existing installer runCommand check, run the
       extracted partitioning call against a `truncate`d image with
       `pkgs.gptfdisk` and an impossible root range, and assert that
       `sgdisk -p` lists no partition afterwards.
   - → verify by building both checks.

4. **agy: modules (fixes 9–12, and 13 as no-edit).**
   - `modules/services/open-webui.nix:71`: `lib.mkDefault` on the four
     values.
   - `modules/fleet.nix`: `:41` `default = ""`; `:69`, `:70`, `dates`, `:88`
     `lib.mkDefault`; `:115` `${lib.escapeShellArg cfg.url}` (drop the
     surrounding double quotes).
   - `modules/auto-update.nix:142`: `-d` → `-e`.
   - `modules/services/tailscale.nix:61`:
     `config.services.tailscale.interfaceName`.
   - `tests/options.nix`: three cases in the existing `rec { on; off; }`
     style, near the webui (`:2085`), fleet (`:2290`) and tailscale cases:
     - webui on plus the user's own `OLLAMA_API_BASE_URL` evaluates, and the
       user's value wins;
     - fleet on plus the user's own `randomizedDelaySec` evaluates and wins;
     - tailscale `trustInterface` with `interfaceName = "ts0"` trusts `ts0`.
     Wire each into the result attrset (`:3220`-ish) the way neighbouring
     cases are.
   - → verify by targeted
     `nix eval .#checks.x86_64-linux.options.drvPath`, which must evaluate.
     Do **not** build `options`.
   - Shell commands run read-only for agy: make edits with its file tools.

5. **Claude: agent bus (fixes 14, 15).**
   - `share/agent-bus/hooks/bus-redact.sh:49` and its header sentence about
     the default.
   - `tests/bus-redact.nix:85` retargeted to `block`, plus a case with
     `AGENT_BUS_ROOM=#agents` set that still allows.
   - `share/agent-bus/agent_bus_mcp.py:418` and `:505`: the first-read
     branch.
   - `tests/bus-mcp.nix`: a python block that patches `httpx.Client` with a
     `MockTransport` homeserver. The first `read_new` must send `dir=b`
     without `from` and return the newest two in order. The second must
     send `dir=f&from=<start>`.
   - → verify by building `bus-redact` and `bus-mcp`.

6. **Claude: try.sh (fix 8).**
   - `installer/try.sh` dry-run block (`trap` line, `classify_plan`).
   - `tests/try-preflight.nix`: after a run whose dry-run succeeds, no
     temp file from it remains under its `TMPDIR`.
   - → verify by building `try-preflight`.

7. **Claude: review, proofs, PR.**
   - A fresh `opus` agent reviews the full diff against this plan.
   - For each new or retargeted case: revert only its fix (`cp` aside),
     build, capture the red line, restore with `cp`, build green. Confirm
     each break landed with `git diff`.
   - `nix fmt -- --ci`, statix, deadnix.
   - Commit: one commit per step, the last carrying the real subject.
   - Agent-bus post per §9 (fix 15's read-from-start is a gotcha other
     agents hit).
   - PR linking all three artifacts, naming who did which step, with the
     failing outputs. `Closes #1274`.

## Tests

The checks named in steps 1–6, each built green, with each new case first
seen red with its fix reverted. CI runs `options`, `install`, `free-space`,
`installer-refusal` and the rest on the PR.

## Rollback

Revert the PR's squash commit. Nothing is deployed and no state format
changes. The bus cursor table is unchanged, since `start` and `end` are both
ordinary pagination tokens.
