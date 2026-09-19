---
status: approved
issue: 765
intent: intent/2026-09-18-765-rebuild-window.md
---

# Spec: the rebuild runs in the Omarchy shell, and asks for the password through the Omarchy dialog

## Design

The track ships as five PRs in the order the intent approved. PR 1 is
specified in full here. PRs 2-5 are outlined, and each gets its own plan step
when it is reached.

### PR 1: the rebuild's elevation goes through polkit (pkexec)

**What elevates today.** Two scripts on the desktop run nh's switch.
`nixarchy-apply` does it at `modules/apps.nix:3326`, reached from Install >
Apply and every per-app row. `omarchy-update` does it at
`pkgs/omarchy/nix-bin/omarchy-update:225`, reached from Update > Nixarchy. Both
leave elevation to nh (`apps.nix:3316-3317`: "No sudo: nh elevates itself").
nh 4.4.2 tries doas, then sudo, then run0, then pkexec, and takes the first one
on PATH (`crates/nh-core/src/command.rs:384`). sudo is always present, so it
always wins. Nothing in `modules/`, `pkgs/` or `installer/` sets
`NH_ELEVATION_STRATEGY` or an askpass.

The change has three parts, all inside `mkIf cfg.enable`, so Mode A is inert:

1. **Both scripts pick pkexec, unless the caller already chose.** Each gets one
   line before it calls nh:

   ```sh
   export NH_ELEVATION_STRATEGY="''${NH_ELEVATION_STRATEGY:-/run/wrappers/bin/pkexec}"
   ```

   Why the scripts rather than the alternatives:
   - A session variable would also change a user's own hand-typed nh and every
     other nh subcommand. That breaks "only the rebuild changes".
   - `programs.nh` has no environment option.
   - A menu-action prefix would miss `omarchy-update` when it is called from
     QML (`pkgs/omarchy/default.nix:1024`).

   The `:-` keeps a user's exported choice. `NH_ELEVATION_STRATEGY=auto`
   restores sudo. It has to be a path: a bare `pkexec` resolves through PATH,
   which only finds the setuid wrapper if the wrapper exists (below). nh reads a
   path as `Prefer`: if the file is missing it logs a warning and falls back to
   auto-detection, which means sudo (`command.rs:337-345`). A machine without
   the wrapper therefore degrades to today's behaviour instead of failing.
2. **The setuid wrapper exists.** In the pinned nixpkgs,
   `security.polkit.enablePkexecWrapper` is a `mkEnableOption`, off by default
   (`nixos/modules/security/polkit.nix:31`), and it gates
   `security.wrappers.pkexec` (`:188-194`). `nixosConfigurations.reference`
   evaluates it to `false` today. Without the wrapper, pkexec is the
   non-setuid store binary, and every elevation fails. So
   `modules/nixos.nix` sets `security.polkit.enablePkexecWrapper = lib.mkDefault true`,
   a scalar at `mkDefault` per `modules/services/default.nix`'s header.
   `security.polkit.enable` is already on (`reference` evaluates it to `true`).
3. **One password per rebuild, not three.** One switch elevates three
   separate commands:
   - `switch-to-configuration test` (`crates/nh-nixos/src/nixos.rs:383`);
   - `nix build --profile` to set the system profile (`:428`);
   - `switch-to-configuration boot` (`:435`).

   pkexec's action, `org.freedesktop.policykit.exec`, defaults to `auth_admin`
   for active sessions (polkit-127, `org.freedesktop.policykit.policy`), and
   that means a dialog for each of the three. The fix is one
   `security.polkit.extraConfig` rule that returns `AUTH_ADMIN_KEEP` for that
   action, when the subject is local, active and in wheel, and the program's
   basename is `env`. nh always elevates `env ...` (`command.rs:659`), so the
   rule matches exactly the nh-shaped calls. It matches on the basename, not
   `/run/current-system/sw/bin/env`: `nixarchy-apply` is a
   `writeShellApplication` with coreutils in `runtimeInputs`, so its PATH
   starts with a store coreutils, and the resolved path of `env` depends on
   the caller.
   `AUTH_ADMIN_KEEP` still requires the admin password. It only lets the same
   subject, here the one nh process, reuse that authentication for polkit's
   retention window instead of asking again. The rule never returns `YES`. The
   intent's "authentication stays required" holds.

**Who answers.** In the Hyprland session, the Omarchy polkit agent is
registered for the session (journal line: "omarchy polkit agent registered",
`shell/plugins/polkit/PolkitAgent.qml:186`) and shows the dialog. Over SSH, or
on a text console, no agent is registered for that session, and pkexec
starts its own text agent on the tty. There the prompt is text, as it is
with sudo today. A caller with no agent and no tty fails authentication.
That is the same as sudo with no tty.

**Callers that do not change.** `checks.session` pipes `echo n` into
`nixarchy-apply` (`tests/session.nix:206`) and never reaches the switch.
`tests/install.nix:930` rebuilds with `nixos-rebuild` as root, on purpose. The
installer does not call nh. nixarchy-pkg's Apply already exports
`NH_ELEVATION_STRATEGY=pkexec` itself, and the `:-` in part 1 leaves that
alone. Its bare `pkexec` only works once part 2 puts the wrapper on PATH, so
PR 1 fixes it by accident.

**Docs.** In `modules/AGENTS.md`, a short section on why the rebuild uses
pkexec and why the rule is `KEEP` rather than `YES`, with a `# Why:` pointer
from both script lines. `docs/manual/other-packages.md` gets a sentence on the
dialog and the `auto` override.

### PRs 2-5, in order (outline)

2. **`nixarchy-apply --yes` and `--no-preview`**, which answer the two
   questions without stdin. Interactive prompts stay when no flag is given.
   The failure message at `apps.nix:3331` becomes "The rebuild failed (exit N).
   Read the log above. `nixarchy rollback` returns to the previous
   generation." It makes no claim about what changed. nixarchy-pkg moves from
   `printf 'n\ny\n'` to `--yes --no-preview` (its #19).
3. **A supervised build.** `nixarchy-apply --yes` runs inside
   `systemd-run --user --unit=nixarchy-rebuild --collect -p RemainAfterExit=yes`
   (not `--scope`, so the unit outlives the caller), with nh's `--no-nom`. The
   output goes to the user journal. The unit's `ActiveState`, `Result` and
   `ExecMainStatus` are the state. A second apply while the unit is active is
   refused. pkexec from a user unit has no tty and relies on the session's agent. Proving
   that agent is reached from a unit belongs to this PR's verification.
4. **The spinner opens the rebuild's log.** `switch-indicator.qml:96` changes
   to `journalctl --user -fu nixarchy-rebuild`.
5. **The panel replaces the terminal.** A first-party Quickshell panel in
   `pkgs/omarchy/`, installed like `switch-indicator.qml` (`default.nix:1857`).
   Its id is not in `omarchy.`, and the shell discovers it through
   `PluginRegistry.qml`'s manifest scan. It shows the step, the elapsed time,
   a bounded log tail read from `journalctl --user -u nixarchy-rebuild -o cat -f`,
   and on failure Copy log and Open full log in terminal. Install > Apply and
   the per-app rows start the unit and open the panel instead of
   `omarchy-launch-floating-terminal-with-presentation`. Closing the panel
   only detaches it, and reopening it reattaches to the same unit.

## Alternatives rejected

- **`SUDO_ASKPASS` / `NH_SUDO_ASKPASS` with a Quickshell askpass helper.** That
  would be a second password dialog and a new channel for passwords, when
  polkit already has an agent running. Kept as the fallback only if pkexec
  turns out to be unworkable.
- **A polkit rule returning `YES` for wheel.** A passwordless switch is
  passwordless root, which the intent forbids.
- **A session-wide `NH_ELEVATION_STRATEGY`.** It changes every nh command
  the user types, not just the rebuild.
- **`run0`.** It needs `--pty-late` and a systemd-run transient unit per call,
  and its behaviour inside a graphical session with no tty is less well
  known here than pkexec's. There is no gain over pkexec, which already
  reaches the same agent.
- **Scoping the `KEEP` rule by the command being run.** The program polkit
  sees is `env`, not `switch-to-configuration`, so the command line is the only
  hook. Matching on it would be fragile across nh versions and would not make
  anything safer: `env` can run anything either way. The real limit is that
  retention is per subject, the single nh process.

## Risks

- **Retention depends on the subject.** "One prompt per switch" holds only if
  all three pkexec calls share one polkit subject (nh's pid and start time).
  This is not verified yet. If it fails, the result is three dialogs, not a
  security regression. Verified on real hardware (below) before the PR merges.
- **pkexec must find `env`.** nh passes a bare `env`. pkexec resolves its
  program before it clears the environment. Not verified by reading pkexec's
  source; the VM probe below covers it.
- **The wrapper is a new setuid binary on every nixarchy machine.** GNOME,
  Cinnamon, MATE, XFCE, Budgie and gamemode all turn the same wrapper on in
  nixpkgs (grep of `nixos/modules`), so it is a standard shape rather than a
  new attack surface. Mode A does not get it.
- **Hand-typed `nixarchy apply` in a desktop terminal** now pops the dialog
  instead of a sudo prompt. This is intended (the rebuild uses the dialog),
  and `NH_ELEVATION_STRATEGY=auto` opts out.
- **CI install jobs.** None call nh or nixarchy-apply, so none change.

## Verification

Every check is broken first, and its failing output goes in the PR (§1).

- **`tests/options.nix`, evaluation:**
  - with nixarchy on, `security.polkit.enablePkexecWrapper` is `true` and
    `security.polkit.extraConfig` contains the rule's action id;
  - the Mode A fixtures (`loaderOff`, `notImported`) keep nixpkgs' `false`;
  - `modeAInert` stays green.

  Break: delete the `mkDefault true`. The first assertion must go red.
- **The scripts, evaluation:** `nixarchy-apply` and `omarchy-update` contain
  the export, read from the built derivations. This proves only that the
  line is written (§2's nixd lesson), which is why the VM probe exists.
- **`checks.session` (VM, OCR already on at `tests/session.nix:170`):** inside
  the user's Hyprland session (`hyprctl dispatch exec`, so the subject is the
  graphical session, not `su`), run
  `/run/wrappers/bin/pkexec env touch /tmp/pkexec-ok`. `wait_for_text` sees the
  agent's dialog. `send_chars` the user's password plus Return. The file
  exists and is owned by root.

  Break: disable the plugin's agent (`disabledPlugins` in the test's
  `shell.json`). pkexec then has no agent, the dialog text never appears, and
  the probe fails. The same probe with the rule removed is not asserted: one
  pkexec call cannot show retention.
- **On real hardware, by hand:** one Install > Apply shows exactly one Omarchy
  dialog and switches. The same apply over SSH prompts as text. The PR records
  both. Retention (Risk 1) can only be checked here: no VM in this repo
  drives a full switch through nh (`tests/install.nix:914` explains why), so
  this is recorded as a hole in `tests/AGENTS.md` per §3.
- `nix fmt -- --ci`, statix and deadnix. `gh run list` shows no install in
  flight before `checks.options` (11.5 GB) or the session VM runs locally (§6).
- No new `checks.<name>`. Both assertions land in existing checks, so no
  workflow edit.
