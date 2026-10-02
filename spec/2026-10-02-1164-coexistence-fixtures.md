---
status: approved
issue: 1164
intent: intent/2026-10-02-1164-coexistence-fixtures.md
---

# Spec: nixarchy is tested beside the user configurations it promises to coexist with

## Two things for the owner to decide on approval

1. **The fonts fixture is dropped (a departure from intent answer 1).**
   - Fonts are not merged into an environment of their own. They reach
     `system.path` through `pathsToLink` (`fontdir.nix:73`), which ignores
     collisions.
   - Two font packages almost never ship the same file name.
   - I found no way a font overlap breaks a build, or silently changes what
     the user gets, that a fixture could assert.
   - A fixture that cannot fail is worse than none (§1). If a real font
     coexistence bug turns up, it gets its fixture then.
2. **A `build.yml` edit, which is a CI-gate change for a human (§4, §11).**
   - The new check needs nixarchy's real packages realised: the real Mesa
     (about 1.1 GB) and the whole `system.path`.
   - The `system` job already builds the reference toplevel, so it holds
     exactly that. Built there, after the toplevel, the check costs little
     more than linking.
   - Anywhere else, `checks.*` lands in the `omarchy` job's "build every
     unclaimed check" step, on a store without the closure. That means about
     20 GB of substitution or building per run.
   - So the check is *claimed* by the `system` job: one added step, and one
     line in the generated-checks `claimed` list. The PR asks for that
     sign-off explicitly.

## What was measured

| merged environment | NixOS definition | on a collision |
|---|---|---|
| `graphics-drivers` / `-32bit` | `nixos/modules/hardware/graphics.nix:10-15`, `pkgs.buildEnv`, no `ignoreCollisions` | **build fails** (#1163) |
| `system.path` (`environment.systemPackages`) | `nixos/modules/config/system-path.nix:207-211`, `ignoreCollisions = true` | **silently resolved**: `meta.priority` first, then order. One package's file *shadows* the other's. |
| fonts | via `pathsToLink` into `system.path` (`fontdir.nix:73`) | as `system.path`; no known failing case (see above) |

So there are two failure modes and two kinds of assertion:
- **graphics:** "it builds";
- **`systemPackages`:** "the user's own package wins where it overlaps one of
  nixarchy's".

The intent's framing ("goes red on a collision") fits only the first. The
second is about shadowing, which nothing tests today.

## Design

### D1. Fixtures: `tests/coexistence/fixtures.nix` (new)

An attrset of plain NixOS modules. **No `programs.nixarchy.*`.** Each is a
user's own setting.

| name | module | why |
|---|---|---|
| `graphics-own-mesa` | `hardware.graphics.extraPackages = [ pkgs.mesa ]` | the commonest user pattern. On `main`, `pkgs.mesa` is Hyprland's path, so this is the "identical Mesa" case, which must build. |
| `graphics-32bit` | `enable32Bit = true; extraPackages32 = [ pkgs.driversi686Linux.mesa ]` | p620's original pattern |
| `graphics-own-package` | `hardware.graphics.package = pkgs.mesa` | the documented escape hatch from #1163 |
| `graphics-opencl` | `extraPackages = [ pkgs.mesa.opencl ]` | Rusticl, which #1165's review found the assertion had nearly rejected |
| `systempkg-own-ffmpeg` | `environment.systemPackages = [ pkgs.ffmpeg-full ]` | nixarchy ships `ffmpeg` (runtime deps). A user who wants `ffmpeg-full` must get *their* `bin/ffmpeg`. |

**Adding a fixture with every coexistence bug** is the standing rule (D4).

### D2. The check: `checks.coexistence` (`tests/coexistence/default.nix`)

- **For each fixture:**
  `reference.extendModules { modules = [ fixture ]; }`.
- **Graphics fixtures:** build the fixture's `graphics-drivers` and
  `graphics-drivers-32bit`, the paths behind
  `systemd.tmpfiles.settings.graphics-driver."/run/opengl-driver"`. They must
  build, and `/run/opengl-driver`'s target must contain a
  `share/glvnd/egl_vendor.d/*mesa*.json`. A fixture whose evaluation hits a
  nixarchy assertion (#1163) counts as a **failure here**: these fixtures are
  configurations we promise work.
- **`systempkg-*` fixtures:** build the fixture's `system.path`, and assert
  that `readlink -f $path/bin/ffmpeg` lies inside the user's package
  (`pkgs.ffmpeg-full`'s outPath), not nixarchy's `ffmpeg`.
- **Output:** one line per fixture, `name: ok` or `name: FAIL <reason>`; it
  exits 1 on any failure.
- **Where it runs:** claimed by the `system` job. One step after "Build the
  installed-machine closure":
  `.github/scripts/build-unless-proven.sh .#checks.x86_64-linux.coexistence`.
  The name goes in the `claimed` list of `.github/scripts/generated-checks.sh`.
  - **The plan measures** the step's wall time on a warm store.
  - The `system` job ran 30–43 minutes against its 45-minute limit on
    2026-10-01 and 02. If the step adds more than about 2 minutes, the plan
    stops and reports rather than risk the limit (raising it is the owner's
    call).

### D3. §1 for each kind

- **Graphics.** Re-introduce #1163's state: remove its assertion, and give the
  `graphics-own-mesa` fixture a *different* Mesa. The fixture's `pkgs.mesa`
  equals ours on `main`, so the break also points the fixture at a different
  Mesa, built once from a trivially modified derivation, or Mesa from another
  nixpkgs pin that is substitutable. The plan picks whichever is substitutable.
  It must go red with the `buildEnv` collision line. Run on a probe branch
  through CI, as before.
- **`systemPackages`.** Give nixarchy's `ffmpeg` a higher priority than the
  user's (e.g. `lib.hiPrio` in a probe-only edit). The check must go red,
  naming whose `bin/ffmpeg` won.
- **And if `systempkg-own-ffmpeg` is already red on `main`,** meaning
  nixarchy's `ffmpeg` already shadows the user's, that is a real coexistence
  bug. The plan stops, reports it as a finding, and does not quietly flip the
  fixture's expectation.

### D4. The rule, as an appended AGENTS.md section

A new **§14, "Coexist with the user's own config"**, appended at the end;
never inserted, because §1–§13 numbers are referenced. It says:

- **Whenever a change makes nixarchy set an option a user commonly sets too,**
  the spec gets a *Coexistence* section. It names the merged environment the
  option feeds, and which failure mode applies: the build fails
  (`buildEnv`, no `ignoreCollisions`), silent shadowing (`system.path`), or a
  priority or merge clash.
- **The answer is a fixture in `tests/coexistence/fixtures.nix`,** plus,
  where needed, an assertion or a warning. Never only a sentence in the PR.
  #1162 → #1163 is the worked example.
- **A changed default for a user-facing option is announced** in the release
  notes and the Discussions post, with the migration step (intent outcome 4).

## Alternatives rejected

- **A separate cheap check that builds in the `omarchy` job.** About 20 GB of
  closure per run on a cold store; not cheap.
- **Evaluation-only checks for `system.path`.** Which file wins is decided at
  build time by priority and order; evaluation would re-implement buildEnv's
  rules and drift from them.
- **Testing the owner's real host configs.** Out of scope by the intent's
  constraint; they live elsewhere.
- **A fonts fixture now.** No failing case is known (decision 1 above).

## Risks

- **The `system` job's time limit.** Mitigated by measuring before merge, and
  stopping if the step costs more than about 2 minutes.
- **The ffmpeg fixture finds that nixarchy already shadows the user.** That
  is a real bug: reported, not hidden.
- **The fixtures can age.** A fixture naming a package nixpkgs renames fails
  evaluation, which is loud, and is fixed in the same PR as the rename.

## Verification

1. `checks.coexistence` is green in the `system` job on the PR, with its
   wall time recorded.
2. The graphics and `systemPackages` staged reds (D3) are shown via probe
   branches, with outputs in the PR.
3. The `build.yml` edit carries the owner's explicit sign-off in the PR.
4. AGENTS.md §14 is appended, and no other section is renumbered: `grep` the
   `§1`–`§13` references in `build.yml`, `omarchy.yml` and `tests/bus-mcp.nix`,
   and confirm they are unchanged.
5. fmt, statix, deadnix.

## Owner's decisions (2026-10-02)

1. **The fonts fixture is dropped,** as recommended.
2. **The `build.yml` edit is signed off:** one step in the `system` job, and
   the `claimed` entry. The step-cost limit still applies: stop and report if
   it adds more than about 2 minutes.
