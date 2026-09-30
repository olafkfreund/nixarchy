---
status: draft
issue: 1100
spec: spec/2026-09-30-1100-agent-microvm-egress-policy.md
---

# Plan: Separate an agent MicroVM's egress policy from its writable share

The agent and agent-claude templates currently build tinyproxy's filter from
`/mnt/host/allow-hosts`, but `/mnt/host` is the guest-writable `share/`.
Keep that share for work. Add a distinct `policy/` sibling, exported to agent
guests at `/mnt/agent-policy` with both QEMU 9p `readOnly = true` and a guest
`ro` mount. The pinned microvm.nix revision is
`fdfc1821a0eb76e44a13d206b72e6ca6961fbb7c`: its share option has
`readOnly` (options.nix:408-412), QEMU passes it to `-fsdev` (qemu.nix:291-300),
and its guest mount does not add `ro` itself (mounts.nix:117-131).

Keep immutable `/etc/nixarchy-agent/allow-hosts` defaults, including the
agent-claude endpoints, before the optional per-VM host list. A missing or
empty host list adds no destinations. An actual open/read failure logs the
source and fails the allowlist oneshot, which tinyproxy requires; do not rely
on `[ -r "$src" ]` in a root guest. `dev` remains outside `wheel`, since guest
root can bypass the nftables egress filter. The guest write proof runs as
unprivileged `dev`.

Disposable VMs get `policy/` on create and before run for older VMs. The
owner edits `policy/allow-hosts` on the host. Declarative VMs get a
`microvm:kvm 0750` policy directory from tmpfiles; document a `root:root
0644` file so QEMU's host `microvm` user can read it. That host user owns the
directory and can replace the file; ordinary host users need root privileges
to administer it. The guest cannot write through the policy share. Ignore
old `share/allow-hosts` permanently; tell users to inspect and copy only
wanted entries manually. Never copy it automatically.

## Steps

1. `modules/microvm/templates/agent.nix:39-54,108-163` and
   `tests/microvm-template.nix:98-113,225-313`: add the agent-only 9p share
   with `source = "policy"`, unique tag, mount point `/mnt/agent-policy`, and
   `readOnly = true`; add `fileSystems."/mnt/agent-policy".options = [ "ro" ]`.
   Read `/mnt/agent-policy/allow-hosts` after closure defaults, require that
   mount, remove `/mnt/host/allow-hosts`, and retain empty-filter first,
   hostname validation, and tinyproxy ordering. Check an existing source by
   opening/reading it and catch that operation's failure, log its path, and
   fail the oneshot; a missing file is allowed. Keep `dev` out of `wheel`.
   Inspect the built agent and agent-claude runners and units, not a parallel
   fixture, for `path=policy,...,readonly=true`, a distinct writable
   `path=share`, guest `ro`, the new source and mount dependency, and absence
   of the old source → verify by `nix build
   .#checks.x86_64-linux.microvm-template` under the shared build lock once
   implementation builds are authorized. Traps: `nix fmt`, `git diff --stat`,
   `nix fmt -- --ci`, statix, deadnix; stage new Nix files before flake checks;
   no `producer | grep -q` or `omarchy/shell.json` writes.
2. `pkgs/microvm.nix:250-257,336-345` and
   `tests/microvm-template.nix:358-421`: create an empty `policy/` sibling of
   `share/` for a new VM and immediately before launching a pre-existing VM.
   Refuse a symlink at `policy/` so a stale or hostile path cannot export
   outside the VM state directory. Never read, copy, or delete
   `share/allow-hosts`. Extend the existing real-CLI/stub-runner fixture for
   new and old VMs; leave a legacy list byte-identical and ignored → verify
   by `checks.microvm-template` under the lock when builds are authorized.
   Traps: a test must run the shipped CLI, not a copy of its logic; break
   proof must remove the real creation line.
3. `modules/services/microvm.nix:212-245` and `tests/options.nix:2507-2522`:
   create `<state>/<name>/policy` with tmpfiles as `microvm:kvm 0750` before
   declarative QEMU starts. Correct the comment: a `kvm` group member can
   write `share/` but not `policy/` at this mode. Assert the evaluated
   tmpfiles entry beside the existing `share/` assertion → verify by
   `checks.options` in CI only, never locally. Traps: test the evaluated
   module in its on state, not a hardcoded duplicate; the host `microvm`
   user owns `policy/` and can replace files in it.
4. `docs/manual/sandboxes.md:130-150,173-184,241-262`,
   `docs/manual/ai.md:508-516`, `data/microvm-templates.nix:85-98`,
   `modules/microvm/templates/agent.nix:39-54`, and
   `modules/microvm/templates/agent-claude.nix:24-27`: update examples,
   catalogue notes, and comments to use `policy/allow-hosts` on the host.
   Explain that old `share/allow-hosts` is ignored, manual inspection/copy
   is needed, normal declarative edits use root, `share/` remains writable
   for work, and an allowed host is still an egress route → verify by
   `rg -n 'allow-hosts|/mnt/host|policy/'` over these files and review each
   hit for the intended location. Traps: no bare URLs; no automatic migration.
5. `tests/microvm-boot.nix:60-127`: add a second declarative agent guest with
   a distinct SSH port and `autostart = false`, preserving the existing shell
   guest. After its tmpfiles setup but before starting that guest, write
   a host policy file and an old `share/allow-hosts`; assert the new policy
   is loaded and the old one ignored. Attempts by `dev` to edit or replace
   `/mnt/agent-policy/allow-hosts`, directly or through `/mnt/host`, must
   fail and leave the host file unchanged. Change the host policy and
   restart the guest; assert the changed list is read. Make the host file
   unreadable to QEMU, assert the allowlist journal names the failed read
   and tinyproxy stays down, then restore permissions → verify by
   `checks.microvm-boot` in CI only. Traps: do not run local VM checks;
   preserve the existing shell-guest assertions; do not use guest root for
   the write attempt.

## Tests

- For every added assertion, prove red against a real regression and green
  after restoration. Save each product file with `cp` under
  `/mnt/data/vmtest/` outside the worktree, make one break at a time, inspect
  `git diff` to prove it landed, run the relevant check, capture its failing
  line, restore with `cp`, and rerun green. Never use `git checkout` to
  restore a break.
- Break `agent.nix` three ways: remove share `readOnly = true`; remove guest
  `ro`; point the allowlist source back to `/mnt/host/allow-hosts`. Each must
  make `checks.microvm-template` fail for its own reason. Break
  `pkgs/microvm.nix` by removing run-time `policy/` creation; its pre-existing
  VM case must fail. Break `modules/services/microvm.nix` by removing the
  policy tmpfiles entry; its evaluated assertion must fail in CI, then pass
  after restoration. The guest mutation attempt must fail when the policy
  share is made writable; run that red/green proof in CI, never locally.
- Once builds are authorized, run one build at a time with
  `flock /mnt/data/vmtest/codex-build.lock nix build ...`. Do not run
  `checks.options` or any VM locally. After Nix edits run `nix fmt`, inspect
  `git diff --stat`, then `nix fmt -- --ci`,
  `nix run nixpkgs#statix -- check .`, and
  `nix run nixpkgs#deadnix -- --fail .`. Scan the diff for
  `| grep -q` and writes to `omarchy/shell.json` before a future push.
- Record the red outputs and the final green `checks.microvm-template` run
  in the future PR. CI must report green `checks.options` and
  `checks.microvm-boot` before merge.

## Rollback

Revert this issue's implementation commits together. The previous
`share/allow-hosts` location then becomes active again; inspect its contents
before rollback because that file was guest-writable. No policy file is
deleted by the new implementation, so host-owned `policy/allow-hosts` stays
available for a later reapply.
