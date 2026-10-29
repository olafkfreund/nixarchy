---
status: draft
issue: 1508
intent: intent/2026-10-29-1508-ai-mirror-vsock-cid.md
---

# Spec: hyprland-ai-mirror gets a vsock CID per VM, and a check

The intent's open question takes its default: the docs name both CID
locations, one line each.

## Design

### 1. The CID is chosen at run time

In `modules/microvm/templates/hyprland-ai-mirror.nix`:

- Remove `microvm.vsock.cid = 1504;`.
- Set `microvm.extraArgsScript` to a `writeShellApplication` built from a new
  `modules/microvm/templates/vsock-cid.sh`.

`microvm-run` runs that script as `runtime_args=$(script)` under
`set -eou pipefail` (microvm.nix `lib/runner.nix`). It runs from the VM's own
directory: `pkgs/microvm.nix` `exec_vm` does `cd "$dir"`, and a declared
machine runs from `/var/lib/microvms/<name>`. The script:

- refuses a symlinked `./vsock-cid`;
- if the file is empty or absent, writes a random CID in `3..4294967294`
  (0–2 are reserved, and 2^32−1 is `VMADDR_CID_ANY`);
- refuses a value that is not digits, or that is longer than 10 digits.
  Without the length guard, 2^64+3 wraps to 3 under `$((…))` and passes the
  range check. This was found by a §1 break on the scratch branch;
- normalises with `$((10#…))`, range-checks, and prints
  `-device vhost-vsock-pci,guest-cid=<cid>`.

Diagnostics go to stderr. A refusal stops `microvm-run`, so qemu never starts
on a bad CID.

`pci` is microvm.nix's `devType` once `graphics.enable` is set, which
`hyprland.nix` does. The `microvm.vsock.cid` option produced the same device
line, so qemu sees exactly what it saw before, with a different number. This
script is the scratch branch's, proven there: two VMs at once on KVM, and the
transport on `-tcg`.

Two VMs collide only if their random CIDs match, about 1 in 2^31 per pair. If
they do, qemu refuses to start and names the CID. Deleting the file fixes it.

### 2. Docs

- **`data/microvm-templates.nix` note and `docs/manual/sandboxes.md`.** Drop
  "one at a time" and the fixed CID. The connect line becomes
  `claude mcp add ai-mirror-<name> -- socat - VSOCK-CONNECT:$(cat ~/.local/state/nixarchy/microvm/<name>/vsock-cid):7000`,
  run after the VM's first start. The `$(…)` is expanded when `claude mcp add`
  runs, which is fine because the CID never changes.
- **One line for declared machines.** They keep the CID at
  `/var/lib/microvms/<name>/vsock-cid`.
- **The security paragraph stays.** It is still true, and a CID that is no
  longer fixed is still in `ps`.

### 3. `checks.microvm-ai-mirror`

`tests/microvm-ai-mirror.nix` is a `runCommand` taking `{ inputs, pkgs }` and
registered in `uniformChecks`. It boots nothing.

- **(a) The CID script.** Run the template's own `extraArgsScript`; its string
  context is only that small script. Run it twice in a temporary directory:
  the output has the right form, the CID is in range, it is the same both
  times, and the file holds it. A separate build of the same file is refused
  on `abc`, on a symlink, and on `18446744073709551619` (which wraps to 3).
- **(b) The autoconfirm loop.** Run the unit's own `script` text
  (`config.systemd.user.services.ai-mirror-autoconfirm.script`, which carries
  no store path) under bash, following tests/AGENTS.md "Run a unit's script,
  do not grep it". It runs against a fixture `$XDG_RUNTIME_DIR/ai-mirror/state.json`,
  with `jq` and a stub `ai-mirror` on PATH. A PATH stub works here because
  the script is not a `writeShellApplication`. The stub logs the id only for
  the `confirm` verb.
  - `pending` with id `abc` is confirmed within 3 s.
  - `off` and `agent` are not confirmed in 2 s.
- **(c) Guest wiring, read as values with no store context.**
  - `microvm.vsock.cid` is null, so the fixed CID cannot come back unnoticed.
  - `extraArgsScript` is set.
  - The listener's `ExecStart` contains `VSOCK-LISTEN:7000`.
  - Both units' `path` holds `/run/current-system/sw`.
  - Both units are wanted by `default.target`.

  Before building, `nix derivation show` must list no nixos-system, microvm or
  linux derivation among the check's inputs.

The §1 breaks: remove the CID write; drop the length guard; make the
autoconfirm ignore `pending`; put `vsock.cid = 1504` back. Each must turn the
check red.

### 4. `tests/AGENTS.md`

A short section:
- what the check proves;
- that no CI boots the guest (the #929 wedge), so multi-VM was measured by
  hand;
- that `extraArgsScript` is how a per-VM value reaches qemu without breaking
  one closure per template.

## Alternatives rejected

- **A CID derived from the VM's name by hashing.** It is deterministic, but
  two names can still collide, and the host-side command would have to repeat
  the hash. A file is simpler to read back.
- **The CID in `share/`.** The guest can write there and would choose its own
  address.
- **A CID allocated by `nixarchy vm create`.** It would miss declared
  machines, and it touches the CLI for one template's needs.

## Risks

- **Existing registrations break.** Anyone who ran `claude mcp add … 1504:7000`
  re-adds the server once. The template is hours old, so this hits almost no
  one, and the docs show the new line.
- **`extraArgsScript` runs on the host as the user who starts the VM.** It
  writes one file in the VM's directory and reads nothing from `share/`.
- **Mode A:** untouched, since a template is opt-in. Coexistence (§14): none.

## Verification

- `checks.microvm-ai-mirror` is green, and red under each §1 break.
- Run `test-registration`, `grep-q-pipefail`, statix, deadnix and
  `nix fmt -- --ci`.
- **Live on p620, with CI idle:** two VMs of the template at once, each
  answering MCP over its own CID. Take control without a dialog, `launch foot`
  and see it in `windows`, then record the transcript in the PR. Build from
  the branch and run `microvm-run` from the VM's directory, because
  `nixarchy vm run` builds from GitHub at the system's own commit.
