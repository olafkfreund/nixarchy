---
title: AI
---

# AI

Omarchy's agent tooling — the lazy-loaded launchers, the default agent, the
agents panel in the top bar, crash diagnosis, the local-LLM recommendations —
is upstream's tree running unchanged. `omarchy default agent <name>`,
`Super + Shift + Ctrl + A`, `omarchy agent prompt "..."`,
`omarchy agent crash <pid>`, `omarchy toggle crash-capture` and the
`omarchy-agent-*` commands all work as
[the upstream page](https://omarchy.org/manual/ai/) describes them, and that
page is the reference for how to use them.

Two things differ, and the second matters more than it looks.

## The desktop apps are declared, not installed

The `Install > AI` rows (ChatGPT, Grok Bot, LM Studio, Ollama) do what every
Install row does here: they queue the app in `~/.config/nixarchy/apps.nix`, and
`nixarchy-apply` rebuilds. See
[the philosophy page](philosophy#what-this-does-to-the-install-menu).

The HEY CLI is packaged as `hey-cli` and installs its binary as `hey`. It has
no Install row yet because the Omarchy release nixarchy vendors ships none, so
enable it from your flake:

```nix
programs.nixarchy.apps.hey-cli.enable = true;
```

## The skills are rewritten, because upstream's would lie

Omarchy ships one agent skill, `omarchy`, and symlinks it into the skill
directories of Claude Code, Codex, Pi and the generic `~/.agents/skills`
location, so most harnesses load it automatically. nixarchy keeps the
mechanism — `omarchy-provision-user` symlinks every directory under
`$OMARCHY_PATH/default/agents/skills/` into `~/.claude/skills`,
`~/.agents/skills`, `~/.codex/skills` and `~/.pi/agent/skills` — but ships
three skills instead of one:

| skill | owns |
|---|---|
| `nixarchy` | the desktop: `~/.config/hypr/`, `~/.config/omarchy/`, terminal configs, themes, keybindings, the bar, idle and lock, the `omarchy` commands |
| `nixos` | packages and everything outside `~/.config/`: services, users, hardware, boot, networking, fonts, Home Manager, the flake, rebuilds and rollback |
| `diagnose-crash` | working out why a process dumped core, and where to report it if it is a distribution bug |

The split follows the boundary the rest of this manual keeps drawing: what is
under `~/.config/` is yours and takes effect on save; what is declared in the
flake only changes at a rebuild. An agent that does not know which side of that
line a request falls on will do the wrong kind of change, and the wrong kind is
the one that silently does not last.

### Why `omarchy` could not ship as-is

Upstream's skill is written for Arch. It points the agent at
`/usr/share/omarchy`, which does not exist here, and its decision framework
answers "install a package" with `omarchy pkg add`. On nixarchy that command
prints the declarative route and exits 1; it installs nothing. An agent
following the upstream skill would run it, see a non-zero exit, and either
retry with `pacman` — absent — or fall back to `nix-env -i` or `nix profile
install`, which "work" and then vanish at the next rebuild. That is the one
failure mode that looks like success, so the skill is renamed `nixarchy` and its
front page rewritten rather than patched.

`nixos` is new and owns the install question outright. Its first rule is that
a request that would normally end in an install command ends in a file edit and
a rebuild instead, and it ranks the routes: `nixarchy-app-enable <id>` then
`nixarchy-apply` for an app the Install menu knows; a flake edit and
`nixos-rebuild switch` for anything else; `nix shell nixpkgs#<pkg>` for a
throwaway try that is not meant to be a change to the machine.

`diagnose-crash` keeps its name because `omarchy-agent-crash` reads that path
literally. Its body is upstream's with three corrections: there is no public
debuginfod serving nixpkgs builds, so symbols only resolve if the machine runs
`nixseparatedebuginfod`; "what changed recently" is answered by
`nix profile diff-closures --profile /nix/var/nix/profiles/system` rather than
package mtimes, and `sudo nixos-rebuild --rollback switch` tests the theory; and
a confirmed bug has two possible homes, nixarchy for anything NixOS-specific and
Omarchy for anything that would happen identically on Arch.

### The one thing an agent must be told

A rebuild does not update the session the agent is running in.

`OMARCHY_PATH` and `PATH` are set at login and point at whichever store path was
current then. `nixos-rebuild switch` installs a new package at a *new* store
path and cannot reach into a session that already exists. Every `omarchy-*`
command the desktop runs — every keybinding, every menu row — comes from the old
build until you log out and back in. Home Manager deploying `~/.config/hypr` is
a symlink swap into the store, which Hyprland's auto-reload does not notice, so
that needs `hyprctl reload` too.

Humans lose an evening to this. An agent loses it faster, because its natural
verification — run the script at its full installed path and see that it works
— *passes*, while the keybinding still runs the old one. The `nixarchy` skill
spells out the check:

```sh
echo "$OMARCHY_PATH"
readlink -f /run/current-system/sw/bin/omarchy | sed 's|/bin/omarchy$||'
```

If those differ, the fix is applied and the session is stale. `nixarchy-doctor`
reports the same thing under **Session**. Without this in the skill, an agent
that has just made a correct change will conclude it did not work and start
undoing it.

### Treat the skills as upstream does

Upstream's advice stands: run in plan mode first, and different models use a
skill to different effect. The rollback advice changes, though. Upstream says be
ready to run `omarchy reinstall configs` if the agent makes a mess; here
`omarchy reinstall` cannot finish, because it runs `pacman -Suu` first and the
shim refuses. For desktop config, `omarchy refresh <app>` restores a stock
file. For anything the agent changed in the flake,
`sudo nixos-rebuild --rollback switch` puts back the previous generation.
