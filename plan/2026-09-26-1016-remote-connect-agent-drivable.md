---
status: approved
issue: 1016
spec: spec/2026-09-26-1016-remote-connect-agent-drivable.md
---

# Plan: A person picks a machine, and a desktop opens

Self-contained. The spec and intent do not need opening to implement this.

## The approved decisions, carried over

- **A person connects. Agents are #1018.** AT-SPI does not cross RDP, so
  driving a remote machine wants its accessibility tree over MCP-over-SSH, not
  its pixels through a client. Nothing here serves that; nothing here may be
  shaped around it.
- **The SSH tunnel is the only reach.** No port is opened, `bind` is not
  touched, and the credential is the user's existing SSH key.
- **`sdl-freerdp` is what gets launched.** Measured: `wlfreerdp` prints
  *"client has been deprecated ... As replacement there is a SDL3 based client
  available"* on every run. `xfreerdp` and `sdl-freerdp` have an identical
  flag surface (FreeRDP 3 shares one command line), so capability does not
  decide it -- upstream deprecating its Wayland client in SDL3's favour does,
  and SDL3 needs no Xwayland hop. `xfreerdp` stays as a documented fallback;
  one `freerdp` package ships all three, so this is a launch choice.
- **`/dynamic-resolution`**, because hypr-rdp's default headless output
  resizes to the client. The session follows the window instead of
  letterboxing.
- **The machine list is `~/.ssh/config` plus `tailscale status --json`,
  merged, deduplicated, nothing probed.** Tunnel-only makes SSH the
  precondition, so the SSH config *is* the reachable set. The list says
  "machines you can try", never "machines serving a desktop" -- hypr-rdp
  serves an already-logged-in session, so a machine with nobody at it has
  nothing to connect to.
- **The menu is JSONC rows plus a `gum` wizard**, not QML.
- **The tunnel dies with the client.** A forward nobody can see is a forward
  nobody closes.

## The two open questions, defaulted

Unanswered at the spec gate; both taken as recommended and both cheap to
revisit:

- **No per-machine menu rows.** The `gum` filter reaches a named machine in a
  few keystrokes, and a row per machine is a hand-maintained list of things
  that exist in the SSH config.
- **`serve` and `connect` stay on one command.** A laptop that only connects
  has no use for `serve`, and nothing breaks from carrying it.

## Base: this cannot start until #1017 merges

This branch is cut from `main`. The work extends things that exist only on
`feat/1015-remote-desktop-onboarding`: `pkgs/omarchy/nix-bin/nixarchy-remote`,
the `setup.remote` menu group, the `remote)` dispatcher row in
`modules/apps.nix`, and the `nixarchy-remote` ledger row.

So: **wait for #1017 to merge, then rebase this branch onto the new `main`.**
Do not merge `main` into it and do not stack: #1017 squash-merges, so this
branch would carry the same content twice and conflict. If that happens
anyway, the fix is to cherry-pick this branch's own commits onto the new
`main` and force-push, not to fight the conflict.

Before starting step 1, confirm the base: `git merge-base origin/main HEAD`
is `origin/main`, and `git show --stat` on each commit lists only this
issue's files.

## Deviations, recorded as they happened

**Deviation 1 — step 3 is dropped: `ssh` needs no declaring.** The step rested
on a measurement I made in the wrong place. I checked the omarchy *package's*
references and found no openssh, and concluded the wizard would hit
"command not found". But `runtimeDeps` is exposed through `passthru` and
reaches the scripts via the NixOS module's `systemPackages` -- `bin/` is a
symlink farm, deliberately not `wrapProgram`'d, because a generated wrapper
has no `# omarchy:summary=` comment and the CLI would then report zero
commands. So the package's references were never where `ssh` would appear.

Proven rather than reasoned: with the addition reverted, the reference
toplevel still has `sw/bin/ssh`. The reason is upstream's, not ours --
`nixos/modules/programs/ssh.nix:338` sets
`environment.corePackages = [ cfg.package ]` inside an unconditional
`config = { }` block, so the ssh client is on every NixOS system by
guarantee. A note at the call site records this so the next person does not
re-add it.

**Deviation 2 — the `when`-gate assertion moved to `checks.remote-tunnel`.**
The verification table put it in `tests/options.nix`'s menu pass. That check
costs ~8 minutes and 11.5 GB of RSS, and the property is a grep of the
generated menu -- which `remote-tunnel` already receives, because it takes the
built `omarchy` to read the shipped script. Same assertion, seconds instead of
minutes, and it goes red on a PR without waiting for the expensive job.

**Deviation 3 — `menu-verbs` gained a fix, not just a registration.** Step 4
assumed registering `connect` was all that was needed there. Breaking the
dispatch showed the check dying before its first echo: `verbs_of` ends in a
grep pipeline, an unparseable `case` block matches nothing, and `set -e` took
the check down with no output and an empty `nix log`. `|| true` on the
pipeline plus a `floor` helper that names the CLI were added in the same PR,
because a guard that aborts before it can explain itself is half a check. The
general form is written into `tests/AGENTS.md`.

## Steps

1. Rebase onto the post-#1017 `main` → verify `nixarchy-remote`,
   `setup.remote` and the `remote)` dispatcher row are all present in the tree

2. `data/apps.nix`: a `freerdp` catalogue entry, category matching the other
   network tools, with a `note` saying what it is for and that the machine
   being connected *to* does not need it → verify it appears in the generated
   picker and that `checks.options`' "all N Install rows are mapped" still
   passes

3. `pkgs/omarchy/default.nix`: add `openssh` to the runtime list. **Measured,
   not assumed: `ssh` is in neither the list nor the built package's
   references today**, and the wizard invokes it — an undeclared command is a
   runtime failure no build catches → verify `ssh` resolves from the built
   `share/omarchy/bin` PATH, not merely that the line is in the file

4. `pkgs/omarchy/nix-bin/nixarchy-remote`: add `connect` to the `case` block,
   keeping the `case "${1:-}" in` spelling — `tests/menu-verbs.nix` seds for
   that literal line and a dispatch it cannot parse yields an empty verb list,
   which makes every row pass → verify the check prints `connect` in its
   `nixarchy-remote accepts:` line

5. `nixarchy-remote`: the list — `~/.ssh/config` `Host` entries plus
   `tailscale status --json` peers when `tailscale` is present, merged,
   deduplicated, wildcard `Host *` entries excluded → verify by running it on
   p620 and reading the list against both sources by hand

6. `nixarchy-remote`: the tunnel — a free local port, `ssh -N -L
   <port>:localhost:3389 <host>`, torn down by a trap on every exit path
   including the client's → verify by step 9

7. `nixarchy-remote`: launch `sdl-freerdp` against `localhost:<port>` with
   `/dynamic-resolution`, falling back to `xfreerdp` when only that is
   present. Say the certificate-warning sentence **before** the client opens,
   not after → verify by reading each branch on p620

8. `pkgs/omarchy/default.nix`: the `setup.remote.connect` row in the existing
   `remoteMenuRows` fragment, `when`-gated on
   `command -v sdl-freerdp || command -v xfreerdp`, glyph copied from a row
   that already renders → verify the build-time menu parse and that the glyph
   is a literal, not a `\u` escape

9. `tests/remote-tunnel.nix`: new check, the one part reachable without a
   second machine. Start the wizard's tunnel half against a local listener,
   kill the client, assert no `ssh -N` survives → verify by step 12's break

10. `flake.nix`: register `checks.remote-tunnel`. **No workflow edit**:
    `build.yml`'s `omarchy` job has a step, "Build every check no other job
    claims", that builds everything `generated-checks.sh generated` emits —
    every check not on the `claimed` or `exempt` lists. A new check runs on
    pull requests the moment it exists. Confirm by reading that step's printed
    list in the run log rather than assuming → verify the name appears there

11. `data/bin-ledger.nix`: extend the `nixarchy-remote` reason to the second
    verb, and add whatever behaviour class the ledger check demands for
    spawning `ssh`. **Let the check name it rather than guessing** — it
    already refused this command once until `systemctl-user` was declared →
    verify `checks.bin-ledger`

12. `nix fmt`, then read `git diff --stat`. A managed editor hook runs
    `nixpkgs-fmt` on this machine and the repo uses `nixfmt`; the tell is
    `nix fmt -- --ci` failing once then passing → verify the diff is the size
    of the change

13. `docs/manual/remote-desktop.md`: replace the hand-rolled `ssh -L`
    instructions with the menu row, keeping the SSH-tunnel explanation — the
    shape is still what the row does → verify by reading it as someone with
    two machines

14. `tests/install-matrix.py` and `tests/AGENTS.md`: extend #1015's
    two-machine note to cover the client and the tunnel, and add a step to
    `pkgs/verify.sh` — connect, confirm the session resizes to the window,
    confirm the tunnel closes → verify the note names what is and is not
    covered

## Tests

`gh run list` before every local build: all four runners are on p620 and a
local build competes with in-flight installs.

```sh
nix fmt -- --ci
nix run nixpkgs#statix -- check .
nix run nixpkgs#deadnix -- --fail .
nix build .#checks.x86_64-linux.remote-tunnel --print-build-logs
nix build .#checks.x86_64-linux.menu-verbs    --print-build-logs
nix build .#checks.x86_64-linux.bin-ledger    --print-build-logs
nix build .#omarchy --print-build-logs
```

`checks.options` is needed here and was not in #1015: step 2 touches
`data/apps.nix` and step 8 the menu. It costs ~8 minutes and **11.5 GB of
RSS**, so run it once, deliberately, with nothing else in flight — not
repeatedly while iterating.

**Prove each new check fails first (§1), and put the failing output in the
PR.** Reverting with `git checkout HEAD -- <path>`, never
`git checkout -- <path>`: a flake evaluation needs files staged, and restoring
from the index restores the break. Commit a known-good baseline before the
loop, and after each break prove it landed with `git diff` or a `grep` — a
`sed -i` that matched nothing and a blind check look identical from the exit
status.

| break | must fail with |
|---|---|
| remove the tunnel teardown trap | an `ssh -N` survives the client |
| misspell `connect` in the menu row | `menu-verbs` names the row and the verb |
| remove the `when` gate | the row-gating assertion, on a machine with no client |
| spell the dispatch `case "${1:-serve}" in` | the `remote-verbs` floor, not a row error |
| remove `openssh` from the runtime list | `ssh` does not resolve from the built PATH |

## Rollback

Every step is additive except step 13, which rewrites a documentation section
whose old text is in git.

- Before merge: `git checkout main`, delete the branch.
- After merge: revert the commit. The `connect` verb, the menu row, the check
  and the catalogue entry go; `serve` and `enroll` from #1015 are untouched,
  because nothing here modifies them.
- No user state is involved: the wizard writes nothing, and the tunnel exists
  only while it runs.
