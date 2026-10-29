---
status: draft
issue: 1508
spec: spec/2026-10-29-1508-ai-mirror-vsock-cid.md
---

# Plan: hyprland-ai-mirror gets a vsock CID per VM, and a check

## Approved decisions, from the spec

- `microvm.vsock.cid = 1504` goes. `microvm.extraArgsScript` runs a new
  `vsock-cid.sh` from the VM's directory. The script keeps the CID in
  `./vsock-cid` (beside `share/`), choosing a random one in `3..4294967294` if
  the file is absent or empty. It refuses a symlink, a non-number, or more than
  10 digits; normalises with `$((10#…))`; range-checks; and prints
  `-device vhost-vsock-pci,guest-cid=<cid>`.
- The note and the manual drop "one at a time" and the fixed CID. The connect
  line reads `$(cat ~/.local/state/nixarchy/microvm/<name>/vsock-cid)`, with
  port 7000. One line names `/var/lib/microvms/<name>/vsock-cid` for declared
  machines. The security paragraph stays.
- `checks.microvm-ai-mirror` (cheap tier, boots nothing):
  - (a) the template's own `extraArgsScript`, plus refusals for `abc`, a
    symlink and `18446744073709551619`;
  - (b) the autoconfirm unit's own `script` text, run against fixture
    `state.json` with a stub `ai-mirror` that counts only `confirm`;
  - (c) values only: `vsock.cid` is null, `extraArgsScript` is set, the
    listener has `VSOCK-LISTEN:7000`, both units' `path` holds
    `/run/current-system/sw`, both are wanted by `default.target`.
- Port 7000, the socat listener and autoconfirm are otherwise unchanged.

## Steps

1. **`modules/microvm/templates/vsock-cid.sh` (new) and
   `hyprland-ai-mirror.nix`.** Copy the script verbatim from
   `git show ad50c5a7:modules/microvm/templates/vsock-cid.sh`. That commit is
   on `feat/1504-hyprland-ai-mirror`, and it already has the symlink,
   10-digit, normalise and range guards. In the template:
   - remove `microvm.vsock.cid = 1504;`;
   - add a `vsockCid = pkgs.writeShellApplication { name = "nixarchy-vsock-cid"; runtimeInputs = [ pkgs.coreutils ]; text = builtins.readFile ./vsock-cid.sh; }`;
   - set `microvm.extraArgsScript = "${vsockCid}/bin/nixarchy-vsock-cid";`;
   - update the header comment's "CID 1504 … only one of these runs at a time"
     line to say the CID is per VM, chosen at run time;
   - keep the `pci` suffix: `graphics.enable` makes `devType` `pci`.

   Verify:
   `nix eval --raw .#packages.x86_64-linux.microvm-hyprland-ai-mirror.drvPath`
   evaluates. `git add` the new file first (§5).
   Traps: the nixpkgs-fmt hook, so run `nix fmt` and read `git diff --stat`.

2. **`data/microvm-templates.nix:68` and `docs/manual/sandboxes.md:84,97,102`.**
   - Replace the fixed-CID text with the per-VM connect line, run after the
     first start:
     `claude mcp add ai-mirror-<name> -- socat - VSOCK-CONNECT:$(cat ~/.local/state/nixarchy/microvm/<name>/vsock-cid):7000`.
   - Add one sentence giving the declared-machine path.
   - Remove "One at a time" and "Only one of these runs at a time".
   - In the manual, say several can run at once, each on its own CID.
   - Leave the security paragraph (`sandboxes.md:104-109`) as is.

   Verify: `grep -n '1504' data/microvm-templates.nix docs/manual/sandboxes.md`
   is empty, and `checks.docs-lists` still builds (cheap).
   Traps: the docs checks (`docs-lists`, `readme-counts`) read
   `sandboxes.md`, so build `docs-lists` after the edit.

3. **`tests/microvm-ai-mirror.nix` (new), plus `"microvm-ai-mirror"` in
   `uniformChecks` after `"microvm-boot"` in `flake.nix`.** Adapt the
   scratch-branch file (`git show ad50c5a7:tests/microvm-ai-mirror.nix`) to
   the merged template:
   - (a) unchanged: the template's `extraArgsScript`, run twice, and a separate
     build of `vsock-cid.sh` for the three refusals;
   - (b) replaces the old autogrant test. Take
     `noCtx cfg.systemd.user.services.ai-mirror-autoconfirm.script` into the
     env as a value and run it with
     `XDG_RUNTIME_DIR=$d PATH=${stub}/bin:${pkgs.jq}/bin:${pkgs.coreutils}/bin timeout N bash -c "$autoconfirmScript"`.
     It reads `$XDG_RUNTIME_DIR/ai-mirror/state.json`, so the fixture writes
     that file. The stub is
     `control) [ "$2" = confirm ] && printf '%s\n' "$3" >> "$CONFIRM_LOG"`.
     Cases: `pending`/`abc` confirmed within 3 s; `off` and `agent` not in 2 s;
   - (c) values (`noCtx = builtins.unsafeDiscardStringContext`):
     `vsock.cid == null`, `extraArgsScript != null`, the listener ExecStart
     contains `VSOCK-LISTEN:7000`, both units' `path` contains
     `/run/current-system/sw`, both `wantedBy` contain `default.target`.

   Before building, `nix derivation show` on the check: its input derivations
   must hold no nixos-system, microvm, linux or systemd derivation.
   Build it green under `flock /mnt/data/vmtest/codex-build.lock`.

   **§1:** each break alone, proved landed with `git diff`, staged, built red,
   restored from a copy and re-staged:
   - (i) drop the `printf … > "$f"` CID write;
   - (ii) drop `| ???????????*` from the `case`;
   - (iii) change `select(.owner == "pending")` to `"pendingX"`;
   - (iv) add `microvm.vsock.cid = 1504;` back.

   Capture each red line, then confirm the restored tree is green.

   Also build `test-registration` and `grep-q-pipefail`, and run statix,
   deadnix and `nix fmt -- --ci`.

   Traps (tests/AGENTS.md):
   - never name a variable `out`;
   - no `| grep -q`;
   - stubs use the `${pkgs.bash}/bin/bash` shebang;
   - use printf, not heredocs, inside `''`.

4. **`tests/AGENTS.md`.** Append a section after the `hyprland` one, saying:
   - what the check proves;
   - that no CI boots the guest (the #929 wedge), so multi-VM is proven by
     hand;
   - that `extraArgsScript` is how a per-VM value reaches qemu, with the
     `devType` note (`pci` with graphics, `device` on a plain microvm).

5. **Live proof on p620** (VM tier: `gh run list` shows 0 in flight).
   1. Build the runner from the branch into
      `~/.local/state/nixarchy/microvm/t1508{a,b}/current`.
   2. Start each with `(cd $dir && exec ./current/bin/microvm-run) > $dir/run.log 2>&1 &`.
      Record each qemu pid via `pgrep -f guest-cid=<cid>`.
   3. Drive each over `AF_VSOCK` port 7000 with
      `scratchpad/mcp-drive.py`, port changed to 7000: initialize,
      `control agent`, poll `status` to `agent` (allow 30 s, since the merged
      template's grant takes up to about 20 s), `launch foot`, `windows`,
      `control off`.
   4. Kill only those pids and remove both directories.

   The transcript goes in the PR.

6. **PR**:
   - link the three artifacts;
   - give the red outputs and the transcript;
   - say which steps the coder did, and that existing `…1504:7000`
     registrations re-add once;
   - `Closes #1508`.

   Before opening it, read the bus; post only if a §9 trigger fired.

## Model split

Steps 1–3 edit files, so they go to one `coder`, step by step. The coder
stages and I commit. Steps 4–6 are mine. Review is a fresh Opus agent given
this plan and `git diff`.

## Tests

| command | expect |
|---|---|
| `nix build .#checks.x86_64-linux.microvm-ai-mirror` | green; red under each of breaks (i)–(iv) |
| `nix build .#checks.x86_64-linux.{test-registration,grep-q-pipefail,docs-lists}` | green |
| statix, deadnix, `nix fmt -- --ci` | clean |
| step 5 | two VMs at once, distinct CIDs, each `PASS` |

## Rollback

Revert the PR. That restores the fixed CID 1504 and the "one at a time" docs.
A VM started meanwhile keeps a stray `vsock-cid` file in its directory, which
nothing then reads.
