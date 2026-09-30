---
status: draft
issue: 1091
author: olafkfreund
---

# Intent: Keep generated configuration files owned by the repository user

## Problem

The issue's ownership claim holds. The installer chowns `/etc/nixos` to the installed user (`installer/install.sh:2021-2062`), and `nixarchy-config-repo` already runs git without sudo when `.git` is writable (`pkgs/omarchy/nix-bin/nixarchy-config-repo:87-94`). Yet the command unconditionally uses `sudo tee` for a missing `.gitignore` (`:570-598`) and for GitHub or GitLab CI files, with `sudo mkdir` for the CI parent (`:711-766`). On a normal installer-owned repository, newly created files and directories therefore belong to root and can prompt for sudo unnecessarily. These writes are conditional, so the issue's word “always” applies to the write paths, not every invocation of the command. The current tests do not exercise ownership of these generated files.

## Proposed outcome

On a user-owned flake, `nixarchy config repo` creates `.gitignore` and an optional CI file and its parent directories as that user, without a sudo prompt. It still works on older or deliberately root-owned flakes by elevating only when the destination requires it. Generated files remain editable by the repository owner on reruns.

## Affected users and systems

Installer-built Nixarchy machines using `nixarchy config repo`, and users with older or custom root-owned flake directories. The command can generate GitHub or GitLab CI configuration.

## Constraints

- Keep the existing managed-install refusal and `wgit` behavior; avoid a blanket ownership change to the repository.
- Choose write permission from the destination or its parent, not solely from `.git` permissions; a CI subdirectory can have different ownership.
- Prove a new ownership check fails with unconditional sudo and passes with the fix. Use a cheap sandbox check; no VM or Nix build in this intent stage.
- Do not edit the criticals PR's installer, microVM, or `tests/options.nix` files. This fix need not touch them. No workflow gate changes are needed for generated CI file ownership.

## Open questions

1. **Owner decision:** Use sudo only for legacy flakes that are already root-owned. A normal user-owned flake must not prompt for sudo to create these files.
2. **Owner decision:** Do not implicitly chown existing root-owned files. Preserve existing ownership and keep the fix limited to the generated writes.
