---
status: approved
issue: 950
spec: spec/2026-09-24-950-apply-flake-interface.md
---

# Plan: an environment-independent way to ask which flake nixarchy rebuilds

## The approved decisions, carried over

Self-contained; nothing here needs the intent or spec open.

1. **A file, not a flag.** `environment.etc."nixarchy/flake".text = cfg.flake;`
   beside the existing `environment.etc."nixarchy/managed"`
   (`modules/nixos.nix:1434`), whose register entry is titled *"The ownership
   marker, for the shell tools that cannot ask the module system anything"*
   (`modules/AGENTS.md:448`). That is this issue's problem statement, already
   solved once, with the mechanism and the directory in place.

2. **The scope is the interface only.** Converting the 17
   `${NIXARCHY_FLAKE:-/etc/nixos}` sites is **withdrawn**: the intent's claim
   that the option was ignored was false. `modules/nixos.nix` sets
   `NIXARCHY_FLAKE = cfg.flake` in `environment.sessionVariables`, so inside a
   session every one of them already resolves to the option.

3. **What remains, and is real:** `sessionVariables` exist only in a session. A
   systemd unit, a `sudo` without a login shell, or a plugin spawned outside the
   session gets `/etc/nixos` whatever the option says -- and that is the best
   explanation for nixarchy-flatsnap scraping `nixarchy-apply`'s source, since a
   plugin cannot trust its own environment to carry the answer.

4. **Resolution order is unchanged:** `NIXARCHY_FLAKE` if set, else the option.
   The file carries the option's value. A reader spells it
   `${NIXARCHY_FLAKE:-$(cat /etc/nixarchy/flake 2>/dev/null || echo /etc/nixos)}`.

5. **No `--print-flake` flag**, no change to the default, and
   `modules/auto-update.nix`'s own `flake` option is not touched.

## Confirmed while writing this, not assumed

- **The option is at `modules/apps.nix:1114`**, `type = lib.types.str`, default
  `/etc/nixos`. The spec cited `:1082`; four merges moved it. Re-read at the
  point of edit rather than trusted.
- **The installer already sets it.** `installer/host.nix:55` and `:197` both
  write `flake = "/etc/nixos"`, so the generated host carries the option and the
  file follows with **no installer change**. The spec left this open.

## Steps

1. **`modules/nixos.nix`, in the `environment.etc` block at `:1432`** -- add:

   ```nix
   # The flake `nixarchy-apply` rebuilds, for the tools and plugins that
   # cannot ask the module system and cannot rely on the session environment
   # (#950). environment.sessionVariables carries NIXARCHY_FLAKE for anything
   # inside a session; a systemd unit, a bare sudo and a plugin spawned
   # outside one get none of it, and answered /etc/nixos regardless of this
   # option. Declarative for the same reason nixarchy/managed is: it is in
   # the closure and rewritten by every rebuild, so it cannot go stale
   # against the option it is generated from.
   "nixarchy/flake".text = cfg.flake;
   ```

   No `mkIf`: `cfg.flake` has a default, so the file exists on every machine
   where this module is on. That is deliberate -- a reader wants one answer,
   not "the file is there when someone changed the default".
   → verify by step 3.

2. **`docs/internals/` or `modules/AGENTS.md`** -- one short entry beside the
   `nixarchy/managed` one, since that is where the reasoning for this shape
   already lives, naming the consumer (a plugin that runs apply) and the
   resolution order a reader must use.
   → verify by reading it back; no build effect.

3. **`tests/options.nix`** -- one case, both states:
   - **on:** with `programs.nixarchy.flake = "/home/alice/nixos-config"`, the
     file's **text** equals that path.
   - **off:** on a default machine the text is `/etc/nixos`.

   The assertion reads `.text`, never `? "nixarchy/flake"`. Presence is free the
   moment the attribute is written and would pass with `cfg.flake` replaced by a
   literal -- which is the whole bug. Section 1: the case must go red with
   `cfg.flake` swapped for a hardcoded `"/etc/nixos"`, and that output goes in
   the PR.
   → verify by running it broken, then fixed.

4. **No new `checks.<name>`**, so no workflow edit and no CI-gate change --
   unlike #959, this rides on `checks.options`, which every workflow already
   builds.

## Tests

| command | expected |
|---|---|
| `nix build .#checks.x86_64-linux.options` | passes, including the new case |
| `nix fmt -- --ci`, statix, deadnix | clean |
| `.github/scripts/readme-counts.sh --check` | rc=0, no derived count moves |

Section 1 evidence to capture: the case red with `cfg.flake` replaced by a
literal, green with it restored.

Queue check before the heavy build (`gh run list`), per section 6.

## The spec's open question, decided

Trailing newline: **none.** `environment.etc.<name>.text` appends nothing, so
`cat` returns the bare path and `$(cat ...)` would strip a newline anyway. A
reader doing `read -r < /etc/nixarchy/flake` also gets the path either way. No
newline is the simpler thing to describe, so it is what the docs entry states.

## Rollback

`git revert`. One file disappears from `/etc` at the next rebuild. Nothing reads
it yet inside this repo -- the consumer is nixarchy-flatsnap, in another
repository, which still has its `sed` fallback and is not changed here (section
11: not ours to file). So a revert cannot break anything that was working.
