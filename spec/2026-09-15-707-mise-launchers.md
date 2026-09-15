---
status: approved
issue: 707
intent: intent/2026-09-15-707-mise-launchers.md
---

# Spec: first login stops installing mise launchers that shadow Nix agents

## Design

Decide per tool, at the moment a launcher would be written, instead of keeping
a hand-written list. The rule: a mise launcher exists only when Nix does not
already provide the command.

- **D1. `omarchy-mise-install` skips a command Nix already provides.** This is
  a `substituteInPlace` in `pkgs/omarchy/default.nix`, next to the
  `omarchy-refresh-applications` patch. Before `rm -f "$HOME/.local/bin/$command"`,
  look the command up on PATH with `~/.local/bin` removed. If it resolves, print
  that it is skipped and `exit 0`.

  Both callers go through this one script: first login through `mise.sh`, and
  `omarchy-refresh-applications`. So a single guard covers both, and `mise.sh`
  and `all.sh` stay untouched.

  omp, ghui, hunk and muse have no Nix package and still get launchers, exactly
  as upstream does. So does codex on a desktop that never picked codex from the
  Install menu, which means no tool disappears from a desktop that did not
  choose one.

- **D2. A rebuild removes launchers that shadow a Nix package.** Add a new
  `pkgs/omarchy/nix-bin/omarchy-mise-unshadow`, shaped like the other
  `nix-bin` scripts. For each file in `~/.local/bin`, it deletes the file only
  when both of these hold:
  1. the file is upstream's wrapper: it contains a line matching
     `^exec mise x ` and a line matching `^mise use -g --quiet `;
  2. a command of the same name exists in `/etc/profiles/per-user/$USER/bin`
     or `/run/current-system/sw/bin`.

  Every file that does not match that shape is the user's, and the script
  leaves it alone. `modules/home.nix` runs the script from a Home Manager
  activation step.

  This covers two cases. Existing machines are the first: p620 has had its
  launchers since 2026-09-07. The second is a tool picked from the Install menu
  after first login. Picking it is a rebuild, and that same rebuild removes the
  launcher.

- **D3. One cheap check, `checks.mise-launchers`,** as a stubbed `runCommand`
  in `tests/mise-launchers.nix`, following `tests/theme-set-zed.nix`.
  - (a) With a fake Nix `codex` on PATH, `omarchy-mise-install codex` writes
    nothing.
  - (b) Without it, the script writes upstream's wrapper, so upstream behaviour
    is kept.
  - (c) `omarchy-mise-unshadow` removes a wrapper whose command the fake
    profile provides.
  - (d) It keeps a wrapper whose command no profile provides.
  - (e) It keeps a user's own script that happens to share a name.

  Wiring it into `build.yml` is a CI-gate edit (AGENTS.md §4, §11). Approving
  this spec is the maintainer's sign-off for that one line.

**Change from the approved intent.** Answer 1 there said to keep mise launchers
only for omp, ghui, hunk and muse. D1 reaches the same result without a list,
and without removing codex from a desktop that never installed it through Nix.
That desktop would otherwise have no `codex` at all.

## Alternatives rejected

- **Delete lines from `mise.sh` and drop it from `omarchy-refresh-applications`
  (the issue's suggestion).** Agents in nixarchy are opt-in through the Install
  menu (`data/apps.nix`), so this would remove codex, claude and the others
  from every desktop that did not pick them. The list would also drift every
  time upstream adds a tool.
- **Reorder PATH so the Nix profiles come before `~/.local/bin`.** That breaks
  every tool users deliberately install into `~/.local/bin`, and it changes
  more than this bug needs.
- **A wrapper that tries Nix first and falls back to mise.** It still runs
  `mise use -g` on the fallback path and leaves a file that looks like
  shadowing. D1 plus D2 are simpler: no wrapper at all when it is not needed.
- **A `checks.session` assertion after first login.** It costs about 20
  minutes, and the session VM installs no agents, so it would pass without the
  fix.

## Risks

- **Removing a file the user needs.** D2 is guarded twice, on the exact
  upstream wrapper shape and on a Nix command of the same name. A user's own
  script fails the first guard.
- **The upstream wrapper text changes.** D2 then stops matching and stops
  removing anything, so it fails open (harmless). D1's `--replace-fail` fails
  the build loudly instead.
- **mise-installed agents stop being found.** `omarchy-default-agent` falls
  back to mise shims. Where Nix provides the agent, the Nix one is found first
  anyway.
- **Mode A.** Only the omarchy package and the nixarchy Home Manager module
  change. A host that imports the module without enabling it gets neither.
- **Hosts:** every nixarchy desktop, on the next rebuild. p620 is the one with
  known launchers.

## Verification

- `checks.mise-launchers` passes (a)–(e), and has been seen red twice:
  - with D1's guard removed, (a) fails;
  - with `omarchy-mise-unshadow` not deleting anything, (c) fails.
- `checks.options` and `checks.session` stay green (§6 local-check rule for
  `modules/`).
- By hand on p620 after the change: `command -v codex` resolves under
  `/etc/profiles`, and `codex` starts with no bubblewrap warning.
