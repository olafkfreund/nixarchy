---
status: approved
issue: 1289
author: olafkfreund
---

# Intent: Setup ▸ Language works on NixOS

## Problem

Omarchy `quattro` adds **Setup ▸ Language** (`omarchy-language`). It sets the
interface language and the session's `LANG`. When the chosen locale is not
present, it generates one at runtime: `omarchy-locale-generate` uncomments it
in `/etc/locale.gen` and runs `locale-gen`, through sudo or pkexec.

On NixOS that cannot work. The locales a machine can use are
`i18n.supportedLocales`, fixed at build time. nixarchy sets only
`i18n.defaultLocale = "en_US.UTF-8"` (`installer/host.nix:587`), so in
practice a machine has C and `en_US`. On edge the command is a named `/usr`
exception (#1280). Choosing any other language fails at the generate step,
and the interface and `LANG` do not change together.

Stable `v4.0.4` does not have the feature yet. It arrives with the next
release cut from `quattro`, and the edge channel is where it shows today.

**Measured** (glibc locale archive, 2026-10-15):

| locale set | size | how it arrives |
|---|---|---|
| C + `en_US` (today) | 3 MB | — |
| Omarchy's 50 registry locales | 273 MB | built on every machine |
| every glibc locale | 223 MiB | substituted from cache.nixos.org |

`omarchy-language` already skips generation when `locale -a` lists the
locale. So the fix is to have the locale present before the user picks it.
That can mean every locale up front, or the one picked, added by a rebuild.

## Proposed outcome

- Picking a language in **Setup ▸ Language** changes the interface and the
  session's `LANG` together. Generation never touches `/etc/locale.gen` or
  runs `locale-gen` on a NixOS machine.
- The choice survives a rebuild, a reinstall from the user's flake, and a new
  login.
- The user is told plainly when a rebuild is needed, and is never left with
  the interface switched and `LANG` behind it, which is upstream's own rule.
- `omarchy-language` and `omarchy-locale-generate` leave edge's named `/usr`
  exceptions, and #1280's language item closes.

## Affected users and systems

- **Who:** anyone who uses Setup ▸ Language. Today that is edge only; on stable
  from the release that brings it.
- **Code:**
  - `modules/nixos.nix` (locales, gated);
  - `pkgs/omarchy/default.nix` (patching the two commands, once a stable tag
    carries them; until then an edge carry);
  - possibly the app-selection machinery in `modules/apps.nix`, if the choice
    is recorded the way app picks are;
  - checks.

## Constraints

- **Mode A is untouched.** No locale is added to a machine that did not turn
  nixarchy on, and a user's own `i18n.*` choices win: plain assignment on
  lists (§7), and `mkDefault` on scalars.
- **Upstream's rule holds:** interface and `LANG` switch together or not at
  all.
- **Nothing is generated at runtime under `/etc`**, and no new passwordless
  sudo rule is added. The passwordless-sudo row is hidden on edge for the
  same reason.
- **Cache budget.** The full locale set is substituted from cache.nixos.org,
  not nixarchy.cachix.org, so `cache-budget.sh` is unaffected either way. A
  50-locale subset would be built on every machine.
- **Edge first.** Patches to commands `v4.0.4` lacks cannot go on `main`
  (`--replace-fail` would fail the stable build). The module side can, and
  the command side is an edge carry until a stable tag brings the commands.

## Open questions

1. **Every locale up front (A), or one per pick and a rebuild (B)?**
   - **A:** `i18n.supportedLocales = [ "all" ]` under nixarchy.
     - **Pro:** switching is instant, it works offline, and there is no
       code beyond deleting the generate step.
     - **Con:** about 220 MB on every machine, for a feature most users
       touch once.
   - **B:** Setup ▸ Language records the language (for example
     `programs.nixarchy.language = "da"`, kept in the user's nixarchy
     selection as apps are), adds that one locale through `i18n`, and asks
     for a rebuild.
     - **Pro:** a 3 MB machine stays a 3 MB machine.
     - **Con:** one rebuild per new language, and more code: a selection
       writer, an apply prompt, and a patched `omarchy-language`.
   - **Middle ground:** A, behind an option that defaults on only where the
     installer set a non-English locale or `programs.nixarchy.language` is
     set.
2. **Does the installer ask for a language?** Today it sets `en_US`. If B,
   the installer's own choice could seed the selection. Out of scope unless
   wanted.
