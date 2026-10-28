---
status: draft
issue: 1491
intent: intent/2026-10-28-1491-arch-launcher-flags.md
---

# Spec: the browser flags Omarchy seeds reach the browser

## Design

Three changes, each with its own check.

### 1. A Chromium launcher that reads the flags file

`pkgs/omarchy/default.nix` takes `chromium` and puts it in `runtimeDeps`
(`:82`, `:260`). In its place goes `chromium-flags`, a `symlinkJoin` of
nixpkgs' `chromium` whose `bin/chromium` and `bin/chromium-browser` are
replaced by one small script. Each start, the script:

- reads `${XDG_CONFIG_HOME:-$HOME/.config}/chromium-flags.conf` if it exists,
  one flag per line, skipping blank lines and `#` comments, as Arch's
  `/usr/bin/chromium` does;
- rewrites every `/usr/share/omarchy/` prefix to `$OMARCHY_PATH/`, falling
  back to `/run/current-system/sw/share/omarchy/`. That fixes the file
  already seeded into existing homes without touching it;
- folds every `--enable-features=` into one, and adds
  `WaylandWindowDecorations` when `NIXOS_OZONE_WL` and `WAYLAND_DISPLAY` are
  both set. Chromium keeps only the last `--enable-features`, and nixpkgs'
  wrapper (`chromium/default.nix:141`) puts its own first, so without the fold
  the file's would silently drop nixpkgs';
- `exec`s nixpkgs' `${chromium}/bin/chromium` with the file's flags, then
  `"$@"`, so a caller's own flags still win.

The `.desktop` entries, icons and everything else come through the
`symlinkJoin` unchanged. The launcher is a separate file,
`pkgs/omarchy/chromium-flags.sh`, so a check can run it against a stub.

The seeded `config/chromium-flags.conf` is left verbatim. The launcher's
rewrite covers it, and the user's own edits keep working.

### 2. Native messaging hosts registered at a stable path, at activation

- `omarchy-install-chromium-copy-url` and `-ytdlp` are patched
  (`substituteInPlace --replace-fail`) so that `HOST_PATH` is
  `/run/current-system/sw/bin/omarchy-chromium-{copy-url,ytdlp}-host`
  rather than `$OMARCHY_PATH/bin/...`, which garbage collection removes
  after an update. Each patch gets its row in `data/bin-ledger.nix`, in the
  same change.
- Home Manager's activation (`modules/home.nix`, beside `nixarchySeed`)
  runs both scripts at every activation, standing in for upstream's
  `install/user/chromium.sh`. Both scripts are idempotent, since they rewrite
  the same JSON, and a failure warns rather than failing activation, as the
  seed step does.

### 3. Omarchy's managed policy

`environment.etc."chromium/policies/managed/omarchy.json".source` points at
`${cfg.package}/share/omarchy/default/chromium/policies/omarchy.json`, in
`modules/nixos.nix` beside the existing `color.json` tmpfiles rules
(`:1897-1910`). That is the same file name upstream installs. It is not
`programs.chromium`, which owns `default.json`, so a user's
`programs.chromium.extraOpts` and ours are two files Chromium merges.

## Coexistence (§14)

- **`programs.chromium` set by the user.** It writes
  `/etc/chromium/policies/managed/default.json`, and ours is `omarchy.json`,
  so there is no shared path and no merge. Fixture in
  `tests/coexistence/fixtures.nix`: a config with
  `programs.chromium = { enable = true; extraOpts.Foo = 1; }` builds, and both
  files exist.
- **A user's own `chromium` in `systemPackages`.** `runtimeDeps` go in as
  `lowPrio` (`modules/nixos.nix:1389-1398`), so the user's binary wins and
  ours is shadowed. They lose the flags file, which is what they chose, and
  nothing breaks. No fixture: no failing case exists.
- **The user's own `environment.etc` entry at `omarchy.json`.** Two
  definitions of one `etc` path fail evaluation loudly. That is acceptable for
  a path named after Omarchy, and no fixture is needed.

## Alternatives rejected

- **Bake upstream's flags in with `chromium.override { commandLineArgs }`.**
  Owner's decision: it ignores the user's file and can't fix existing homes.
- **Rewrite `/usr` in the seeded file at build time.** The seed never
  overwrites (`cp --update=none`), so every existing home would keep the
  broken file. The launcher's rewrite covers both.
- **`programs.chromium.extraOpts` for the policy.** It needs
  `programs.chromium.enable`, which is a Mode A change to a module the user
  may own.
- **Writing the host manifests ourselves from Nix.** It duplicates
  upstream's twelve profile directories and the manifest template, which the
  install scripts already carry.

## Risks

- **A flag in the user's file now takes effect.** Until now none did, so a
  bad line a user wrote long ago could change Chromium's behaviour after
  this lands. Release notes say so (§14's announce rule).
- **`OMARCHY_PATH` unset** (Chromium launched outside the session, from
  cron, say): the fallback covers it.
- **The host scripts run at every activation.** They write under
  `~/.config` for browsers that may not be installed. Upstream does the same.
- **The flags rewrite assumes upstream's flags file stays one flag per
  line.** Arch's launcher assumes that too.

## Verification

- `checks.chromium-flags` (new, `runCommand`): the launcher runs against a
  stub `chromium` that prints its argv, over a fixture flags file with
  comments, blank lines, `/usr/share/omarchy` paths, two
  `--enable-features` lines and a caller argument. It asserts the mapped
  paths, one merged `--enable-features` (with and without
  `NIXOS_OZONE_WL`), that caller args come last, and that a missing file
  passes only `"$@"`. Red proof: drop the rewrite, and the `/usr` assertion
  fails.
- `checks.session` (§2, the highest layer that can see it):
  - after login, both NativeMessagingHosts manifests exist and name
    `/run/current-system/sw/bin/...`, never `/nix/store`;
  - `/etc/chromium/policies/managed/omarchy.json` exists;
  - `chromium --headless --remote-debugging-port` lists service workers for
    `bgpiichlckmfanooecilcjemknkcpngb` and `dedjgknigfeelejglamclffonmophnfl`,
    which is the reporter's own proof.

  Red proof: the probe run against `main`'s package fails on the
  service-worker assertion.
- `checks.coexistence`: the new fixture.
- The `/usr` scan in `tests/session.nix:1771` stays green with no new
  exception.
- Cheap tier, `nix fmt -- --ci`, statix and deadnix before pushing.
