---
status: draft
issue: 1649
intent: intent/2026-11-06-1649-reinstall-names-machine.md
---

# Spec: A reinstall image installs the machine it was built from

## Design

The image carries a small git repository and the machine's name, and its launcher passes them as `--from` and `--host`. From there it is the existing `--from` install, so `install.sh` gains one small step for the remote and one for a missing disk.

### The image

- `mkUserIso` passes `host` alongside `flake` in `source`. The published image passes neither, so it behaves as it does today.
- `installer/cd.nix` builds the repository when `source.host` is set: a `runCommand` that copies `source.flake.outPath`, makes one commit with a fixed identity and date, and outputs a bare repository. The launcher names that store path, which is what puts it on the image. It holds only what the flake's source already holds, and no closure.
- **No history and no remote.** A flake's source has no `.git`, and pure evaluation can't read the original's. The new `/etc/nixos` starts from one commit of the tree the image was built from.
- `cd.nix` exposes the launcher as `system.build.installerLauncher`, so a check reads the launcher a real image would run.

### The launcher

After reading `/proc/cmdline`, the launcher adds the image's own `--from file://<repo>` and `--host <name>` only if the command line named **neither**. If it named both, those win. If it named one, the image adds nothing, so `main()` refuses with its existing "needs both" error. That is the intent's "as a pair", with no new code in `install.sh`.

`nixarchy.answers=` combines with the image's pair as it does with a typed one: the answers file is the consent, and the disk still comes from the host.

### After the clone

`clone_repo` drops `origin` when `$from_repo` is a `file:///nix/store/` URL, because a remote pointing into the live system's store means nothing on the installed machine. The commit stays, and `install_flake_dir` already copies `.git`. The manual says to run `nixarchy config repo` to connect the new `/etc/nixos` to a remote.

### A different disk on the new machine

This is the intent's question 2, for any interactive `--from` install of an existing host, including one from a pushed repository, since that person has the same problem.

A new function runs just before `confirm_repo_disks`. It evaluates the host's disks as `confirm_repo_disks` does, and acts only when **all** of these hold:

- the host names exactly one disk, and it isn't on this machine;
- `hosts/<name>/default.nix` holds that path as a literal `device = "<path>";` and `mode = "whole";`;
- the session is interactive.

It then says the saved disk is missing, offers `disk_rows` (from #1653, so the boot medium and floppy are already gone), replaces the path in that file, and runs `git add`. `confirm_repo_disks` then names the chosen disk and asks before erasing, as it does for every other install.

In every other case, today's refusal stands: several disks, a device written some other way, free-space mode (which describes partitions on one specific disk), or an answers file, which is unattended and has no one to ask. A saved path that exists is used, and `confirm_repo_disks` shows its model and serial so a person can say no.

### The command and the manual

- `nixarchy-reinstall-iso` loses `refuse_stock_image` and builds again. Its default attribute becomes `$FLAKE#<this host>-net`, because `reinstall-iso-net` throws on a repository with several machines and the command already knows which machine it's on. `NIXARCHY_REINSTALL_ATTR` still overrides it.
- `docs/manual/reinstall-image.md` loses "Not available right now", and gains the one-commit `/etc/nixos`, what happens on a different disk, and the questions the image asks: consent to run the repository's Nix, network, password and recovery password, and the disks it will erase. It asks for no username.
- The release notes and Discussions post say the command works again.

## Coexistence

None for a configured machine: `installer/cd.nix` isn't imported by anything a machine runs, and `mkUserIso` keeps its signature. A generated flake that already calls `mkUserIso { flake; host; }` gets this on its next pin bump.

## Alternatives rejected

- **Teach `install.sh` to read a store path.** That's a second route to the same place, and `clone_repo`'s `git clone` is already tested.
- **Carry `/etc/nixos/.git` for history and remote.** Pure evaluation can't read it, and it could hold anything the person ever committed and later removed, including a secret. An image is easy to lose.
- **Ask for the disk in `finish_clone`, or edit `disk-config.nix`.** The device is in `hosts/<name>/default.nix` (`installer/template/host/default.nix:29`), and `confirm_repo_disks` is where the refusal lives.
- **Promise only a same-path replacement.** The owner approved the wider promise.
- **A full install of a personal image in CI.** The owner approved the smaller check, and `tests/install-matrix.py` names the hole.

## Risks

- **Erasing the wrong disk.** The replacement disk only changes which disk `confirm_repo_disks` names. The confirmation still stands, and answers-file installs never reach this path.
- **The image is private and now holds a ready-to-clone copy of `/etc/nixos`.** It already held the same files as a store path, and the command and manual still say to keep it private.
- **The target has no cache for something.** The preflight warns on build and the installer checks again on the target, as today.
- **`nix eval` on the clone needs the network** for the flake's inputs. The installer has already asked for it by then, and that's the same as any `--from` install.
- **Git may refuse a repository owned by someone else.** The live image runs as root and the store is root's, so this shouldn't arise, and the plan's check clones as the owner of the path. A booted image is the only full proof.
- **The prompts show a store path** (`file:///nix/store/…`). It's unlovely, and it's also true. No new wording is planned.

## Verification

- **New `checks.reinstall-image`:** evaluates `installer/cd.nix` with a fixture flake and host, takes `system.build.installerLauncher` and the repository it names, and stubs `/proc/cmdline` and the final `exec`. Cases: nothing on the command line passes the image's pair; both named wins; one named passes only that one, and the real `main()` argument check refuses it; `clone_repo` accepts the carried repository, sees the host and has no `origin`; a host absent from the repository takes the existing "adding it" branch, which the check reports so it can't read as this machine; the published image's launcher (no `host`) passes nothing. `mkUserIso` with a wrong host still throws.
- **The disk step, in `tests/installer-from-repo.nix`:** stubbed `lsblk`, `nix eval` and `gum`. Missing saved disk, one candidate: the file is rewritten and staged. Saved disk present: untouched. Several disks, free mode, a device not written literally, and non-interactive: all refuse with nothing written.
- **`checks.reinstall-iso`:** the command reaches `nix build`, with the refusal gone and the attribute naming the host.
- **§1:** remove the launcher's pair and the first case fails. Remove the `origin` removal and the clone case fails. Make the launcher combine a named host with the image's repository and the "one named" case fails. Skip the literal-`device` guard and its case fails.
- **Local, not CI:** build one real image from a throwaway generated flake and boot it in a VM far enough to see the installer name the host. If that fits a slot, the plan says so; a full install on it is named as run or not run in the PR.
- **Named hole:** a full install of a personal image, in `tests/install-matrix.py` and `tests/AGENTS.md`.
