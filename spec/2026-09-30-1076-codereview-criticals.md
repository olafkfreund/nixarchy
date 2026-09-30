---
status: draft
issue: 1076
intent: intent/2026-09-30-1076-codereview-criticals.md
---

# Spec: Fix the code review's critical findings, and the highs in the same places, in one PR

**Scope as approved:** #1076, #1077, #1078, #1079, #1082, #1083, #1084.

**Decisions taken from the intent:**
- #1078 falls back to building when installing into free space.
- The MicroVM share moves to `…/<name>/share`.

The research that led to this spec was done by three read-only agents. Four
bugs were confirmed by evaluating the pinned inputs (A, B1, B2, B4). Two of
the issues' own suggested fixes turned out to be wrong, and are corrected
here (B1, B3).

## Design

### A. #1076: a guest must never share the directory holding `current`

`modules/microvm/guest.nix:47-52` shares `source = "."` read-write over 9p.
It affects both runners:

- **Declarative machines.** `microvm@` has
  `WorkingDirectory=/var/lib/microvms/%i`, and `ExecStopPost` runs
  `current/bin/microvm-unregister` as **root**.
- **Imperative `nixarchy vm`.** `pkgs/microvm.nix` `exec_vm` does
  `cd "$dir"; exec ./current/bin/microvm-run`, and `stop_vm` runs
  `./current/bin/microvm-shutdown` as **the user**. This one is found in
  research and in scope, because the same line fixes both.

**The fix:**
- `source = "share"`, a relative path resolved against each runner's own
  working directory. The mount point stays `/mnt/host`, so templates are
  unchanged.
- The host creates that directory:
  - declarative: a `systemd.tmpfiles.settings."10-nixarchy-microvm"` entry per
    machine, `…/<name>/share`, owned `microvm:kvm`, mode 0770, so the user
    (in `kvm`) can drop `allow-hosts`;
  - imperative: `pkgs/microvm.nix` runs `mkdir -p "$dir/share"` in `create`
    and in `exec_vm`, which also migrates existing VMs. The `hostname` file
    moves into `share/`.
- Today's `"."` already produces a relative tmpfiles entry that
  systemd-tmpfiles rejects. After the fix the relative `"share"` entry is
  equally ignored, which is harmless.

**Docs to update:**
- `docs/manual/sandboxes.md` (`allow-hosts` path, lines 35, 134 and 237);
- the header of `templates/agent.nix`;
- guest.nix's comment claiming the persistent template writes to `/mnt/host`
  (it uses `home.img`).

**Release note:** files guests wrote at the old root are not migrated.
Move them into `share/` by hand. A missing `allow-hosts` fails closed.

### B. #1083: Mode A and MicroVM isolation

1. **`microvm.host.enable`**
   (`modules/services/microvm.nix:201`): `lib.mkDefault (config.microvm.vms != { })`.
   - The issue's `mkIf … (mkDefault true)` is wrong. It leaves upstream's
     `default = true` on every nixarchy-off machine, which turns the four
     `mvOff` rows in `tests/options.nix` red.
   - This form keeps a Mode A user's own `vms` running, and leaves nothing
     when nobody declares any.
   - It does not recurse: upstream never defines `vms` under `host.enable`.
   - The option description notes that a user who runs only imperative
     `microvm -c` must set `host.enable` themselves.
2. **The Hyprland module:** delete `inputs.hyprland.nixosModules.default`
   from `modules/nixos.nix:235`.
   - Nothing in the repository uses the options it declares
     (`programs.hyprland.{plugins,settings,extraConfig,topPrefixes,bottomPrefixes}`).
   - `package`, `portalPackage` and `withUWSM` are nixpkgs options, set under
     `cfg.enable`.
   - Also fix the comment at lines 978-982, which credits a `mkDefault` to the
     wrong module.
   - **Release note:** a Mode A user who set those Hyprland-flake options
     through nixarchy's transitive import must import the flake's module
     themselves.
3. **The agent template** (`modules/microvm/templates/agent.nix`):
   - `users.users.dev.extraGroups = lib.mkForce [ ];` (no wheel, so no
     `sudo nft flush`). `mkForce`, because guest.nix's list merges.
   - DHCP becomes `udp sport 68 udp dport 67 ip daddr { 10.0.2.2, 255.255.255.255 } accept`.
     The issue's "gateway only" would drop the broadcast DISCOVER: the first
     one leaves on an AF_PACKET socket nft never sees, and renewals go
     unicast to 10.0.2.2.
   - `agent-claude` imports `agent.nix`, so it inherits both.
   - Update `docs/manual/sandboxes.md:95,170-173`.
4. **SSH:** `modules/services/microvm.nix:242` becomes
   `services.openssh.enable = lib.mkDefault (m.sshPort != null);`.

### C. #1077: `--from` owns the hostname

In `ask_identity`, when `from_repo` is set, take `hostname=$from_host` and
skip the prompt. The summary screen then shows the real name, and the user
is not asked a question whose answer is ignored.

Also run `validate_hostname "$from_host"` after argument parsing (interactive
`--from` never validated it). This is the #1098 low item, taken here because
it is the same line of reasoning.

### D. #1078, and offline `--from`: the baked reference system only for whole-disk, non-`--from` installs

In `run_install` (`install.sh:2557`), use the baked system only when
`disk_mode = whole` **and** `from_repo` is empty. Otherwise build, with a log
line that says why.

- **Offline `--from`** has the same bug: it copies the reference system
  instead of the repository's machine. It was found in research and taken
  with the same condition. *Decision for approval.*
- Offline free-space then builds. If the image lacks something,
  `rescue_build`'s existing "this is the offline image … missing something"
  message is shown, and nothing is installed. The new line says that for
  free-space this is expected. The other OS is already untouched at this
  point.
- **Named hole:** whether an offline free-space build completes needs a VM.
  That is the `off-free` cell of `tests/install-matrix.py`, which nightly or a
  human runs. It is written down, not claimed.

### E. #1084: the installer's failure path

1. **Retry works:** `install_flake_dir` uses `cp -a "$work" /mnt/etc/nixos`
   instead of `mv`, so a retry can re-format from `$work`. The following
   `git init` is a no-op on an existing repository.
2. **No `exit` inside the phase chain.** These eight `exit`s become
   `return 1`:
   - `partition_free_space` (six: :1457, 1463, 1475, 1492, 1499, 1517);
   - `format_disk`'s unmount refusal (:1559);
   - `reuse_baked_initrd` (:1756).

   The callers check the result, because errexit is off in the chain:
   - `partition_free_space || return 1` at :1566;
   - `reuse_baked_initrd … || return 1` at :1643.

   `nixos-generate-config` at :1640 also gains `|| return 1`, since its status
   is unchecked (found in research, same class).
3. **`--from` with an existing host names the disk before erasing it.** A new
   `confirm_repo_disks`, called after `finish_clone` and before
   `preflight_build`:
   - evaluates `…disko.devices.disk` devices;
   - prints `lsblk NAME,SIZE,MODEL,SERIAL` for each;
   - refuses if a device is missing, or is the installer's own boot medium;
   - then asks with `gum confirm`.

   Unattended (an answers file) prints the list and never prompts: the
   answers file is the consent, per the doctrine at :2807.
- **Out of scope, stated:** retrying a free-space install refuses, because
  it finds its own first-attempt partitions. After E2 that is a clear failure
  screen, not a dead tty. Recognising our own partlabels on retry is a
  separate change.

### F. #1079: installer secrets

1. **`read_answers` parsing:**
   - only a line whose first non-space character is `#` is a comment;
   - `#` elsewhere is data;
   - CRLF is stripped;
   - secret keys (`password`, `luks_passphrase`, `recovery_passphrase`) keep
     their value verbatim, trailing spaces included;
   - other values are trimmed as before;
   - the help text at :178 is updated.
2. **`mkpasswd` via stdin:** `printf '%s' "$pw" | mkpasswd -m sha-512 -s` at
   :650, 702, 1151 and 1167.
   - The ISO's `mkpasswd` is whois 5.5.23, and `-s` exists (verified to give
     the same hash).
   - `printf` is a builtin, so the secret is never in any process's argv.
   - At :1151 the pipe also stops `-s` reading the rest of the answers file.
3. **`nmcli`** (:429): `printf '%s\n' "$pw" | nmcli --ask device wifi connect "$ssid"`.
   - **Risk:** that nmcli reads a piped password under `--ask` is from
     nmcli's source, and not yet tested on a radio.
   - The plan verifies it on the `wifi-hwsim` VM check, which has a real
     mac80211 radio.
   - If it doesn't hold, fall back to `connection add … wifi-sec.key-mgmt wpa-psk`
     plus `connection up … passwd-file <(…)` (losing automatic WEP/SAE
     detection).
4. **`curl`** (:1100): add `--proto =https --proto-redir =https`.
5. **Answers-file cleanup:** `trap 'rm -f "$tmp"' EXIT` right after the
   answers file is fetched (:1098). No earlier EXIT trap exists.
   `ui_dashboard_start` replaces it later, and by then :2831 has removed the
   file.

### G. #1082: the install gate names the real shared files

In `.github/scripts/pr-touches-build.sh:191`, replace the two nonexistent
names with `tests/with-vm-cleanup.nix|tests/vm-cleanup.py`, and correct the
comments at :168, :181-183 and :210. The install checks read nothing else
from `tests/`.

`tests/install-gate.nix:42-43` gains those two cases.

This is CI-gate territory (§11). The owner merges it, and has asked for this
PR.

## Checks: each fails without its fix

| Fix | Check | Layer |
|---|---|---|
| A (declarative) | `tests/options.nix` `microvmProblems`: no share source is `.` or the state directory, plus the tmpfiles rule exists | eval |
| A (imperative) | `tests/microvm-template.nix`: `share/hostname` exists after the run | VM (existing) |
| B1 | `microvmModeAKeepsHost`: nixarchy off plus the user's own `vms` means `host.enable = true` | eval |
| B2 | `hyprlandModeAUntouched`: Mode A has no `programs.hyprland.package` definition from nixarchy | eval |
| B3 | `microvmProblems`: agent `dev` not in wheel, and no `dport 67` without `daddr` | eval |
| B4 | `microvmSshYields`: a machine's own `openssh.enable = true` evaluates | eval |
| C | new `tests/installer-identity-from.nix`: stubbed `gum` returns another name, and `hostname` stays `from_host` | runCommand |
| D | new `tests/installer-baked-guard.nix`: stubbed `nix`/`nixos-install`; free or `--from` records the built system, whole records the baked one | runCommand |
| E1 | `installer-flake-dir` case: `$work` survives `install_flake_dir` | runCommand |
| E2 | a lint: no `exit` in any phase-chain function, plus a behaviour case (`format_disk` in free mode returns `rc=1` and disko never runs) | runCommand |
| E3 | `confirm_repo_disks` cases: refuse on "no", return 0 unattended, refuse a missing disk, serial printed, call order | runCommand |
| F | new `tests/installer-answers.nix`: `p#ss word ` survives, `mkpasswd` argv is logged free of secrets, plus static lines for nmcli argv, `--proto-redir` and the trap | runCommand |
| F3 | `wifi-hwsim`: the piped `--ask` connect succeeds | VM (existing, on PRs) |
| G | `install-gate` cases for the two files | runCommand |

Test files use `printf`, never heredocs inside Nix strings (§5). New checks
are registered in `flake.nix` the way `installer-network` is. The generated
CI step runs them with no workflow edit (§4).

## Alternatives rejected

- **The issues' own fixes for B1 and B3.** Both were wrong, as above.
- **Baking free-space reference variants (#1078).** It roughly doubles the
  reference closures against about 0.9 GiB of ISO headroom. Rejected at
  intent.
- **An absolute share path built from the VM name.** guest.nix does not know
  the name for imperative VMs. The relative path is correct for both runners.
- **`--passwd-file` for nmcli's `device wifi connect`.** That subcommand
  doesn't take one. It is kept only as the two-step fallback.

## Risks

- **Old share contents disappear from `/mnt/host`** for existing VMs. This
  is release-noted; nothing is deleted.
- **Removing the Hyprland module** breaks a Mode A configuration that set
  its options through nixarchy. This is release-noted, and is the point of
  the fix.
- **The nmcli piped `--ask` behaviour** is unverified until `wifi-hwsim`
  runs. The fallback is in the design.
- **The installer changes are in the destructive path.** They are proven
  by `install`, `free-space`, `installer-refusal` and `install-encrypted` in
  CI on this PR; `pr-touches-build` routes installer changes there.

## Verification

- **Every new check, and each existing check it extends, is run red with
  its fix removed** (§1), then green.
- **`checks.options`** runs locally, alone, with CI idle.
- **CI runs the VM checks.** On this PR's CI: `install`, `free-space`,
  `installer-refusal`, `wifi-hwsim`, `microvm-template` and `session`. The
  `off-free` matrix cell is named as the one hole a PR cannot run.
