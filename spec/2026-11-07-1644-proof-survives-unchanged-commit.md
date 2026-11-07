---
status: approved
issue: 1644
intent: intent/2026-11-07-1644-proof-survives-unchanged-commit.md
---

# Spec: A check's proof survives a commit that changes nothing it builds

## Decisions (the intent's open questions, as approved)

1. **The rev leaves `omarchy`.** The module writes `/etc/nixarchy/version`;
   `nixarchy-version` reads it at run time. `omarchy` and everything built
   only from it stop moving per commit. The real system toplevel still moves,
   which is right for it.
2. **The catalogue keeps the commit in its URLs** and its shape
   (`to_entries[]` readers in `modules/apps.nix:3460-3470`, the release asset,
   `tests/nixarchy-options.nix` are untouched). Checks stop seeing the real
   rev by being given a placeholder `self` (below), not by rewriting the file.
3. **Behaviour checks get a fixed placeholder rev**; a short named list is
   exempt because it must carry the real commit or source tree. The real rev is
   still asserted in one cheap, exempt check (`nixarchy-options`, extended).
4. **`build.yml`'s checkout is left alone.** With the rev out of a check's
   closure, the PR merge commit and the later squash commit give the same
   outPath for the same tree.
5. **The guard is a script that compares two real commits**, run by a nightly
   job, not a `checks.*` entry: a flake check cannot evaluate two commits of
   itself.

## Design

### 1. One computation of rev and date, read from `inputs.self`

New `modules/revision.nix`: `self: { shortRev; date; }`, the body of
`flake.nix:530-548` moved verbatim (`self.shortRev or self.dirtyShortRev or
"unknown"`, so a dirty tree still says `-dirty`; the `lastModifiedDate`
fallback to `"unknown"` and its comment come too). `flake.nix` drops
`nixarchyRev`/`nixarchyDate` and the `inherit` at `flake.nix:843`; the
`docs/internals/flake.md` anchor `which-nixarchy-built-this-machine-208-…`
moves with the code (pointer updated, §7).

### 2. `omarchy` no longer carries it

- `pkgs/omarchy/default.nix:9-10` drop the `nixarchyRev`, `nixarchyDate`
  arguments; `1059-1062` keep the `@omarchyversion@` splice only.
- `pkgs/omarchy/nix-bin/nixarchy-version`: the last line reads the first file
  that exists of `/etc/nixarchy/version` and
  `${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy/version` (one line,
  `<shortRev> <date>`, trailing newline), else prints `unknown  unknown`.
  Output format is unchanged (`pkgs/verify.sh:55-62`, `tests/channel.nix:444-466`
  read it). Still no runtime dependency.
- The build-time self-check at `default.nix:1071-1080` becomes two runs:
  `XDG_CONFIG_HOME` pointed at a temp file holding `abc1234 2026-01-02` must
  print both; with no file it must print `unknown`. (No `/etc/nixarchy` exists
  in the sandbox.)

### 3. The module writes the file; standalone Home Manager too

- `modules/nixos.nix`, in the `/etc/nixarchy` block at `1743-1747` (already
  under `cfg.enable`, so Mode A inert): `"nixarchy/version".text =
  "${r.shortRev} ${r.date}\n"` with `r = import ./revision.nix inputs.self`.
- `modules/home.nix`: `xdg.configFile."nixarchy/version"` with the same text,
  only when `osConfig == null` (standalone), so a NixOS + HM home closure gains
  nothing per commit. Standalone users keep the answer they have today.
- `modules/nixos.nix:284` (catalogue `rev = inputs.self.rev or "main"`) and
  `pkgs/microvm.nix:65` are unchanged: both already read `inputs.self`, which
  is what the placeholder replaces.

### 4. Checks see a placeholder `self`

In `flake.nix`'s top-level `let`, beside `stableInputs` (`505-516`) and built
the same way:

```nix
checkInputs = inputs // {
  self = self // {
    rev = "0000000000000000000000000000000000000000";
    shortRev = "0000000";
    lastModifiedDate = "19700101000000";
    nixosModules = self.nixosModules // { nixarchy = import ./modules/nixos.nix checkInputs; };
    homeManagerModules = self.homeManagerModules // { nixarchy = import ./modules/home.nix checkInputs; };
  };
};
```

`checks = eachSystem (system: let realInputs = inputs; inputs = checkInputs; …`
(`flake.nix:1735`) then shadows `inputs` for every check that passes
`inherit inputs` (27 sites, and every future one, so a new check is
proof-stable by default). Explicit fields beat `dirtyRev`/`dirtyShortRev`, so a
dirty local tree gets the placeholder too.

The commit-bound checks must NOT get the placeholder. `install`,
`install-encrypted`, `install-iso-net`, `installer-refusal` and `free-space`
are `uniformChecks` handed `inputs` (`flake.nix:1793-1830`, `2822-2826`); a
placeholder-rev seeded system against an installed machine that evaluates the
real rev would break install's rebuild-builds-nothing. So the generic
`genAttrs uniformChecks` at `flake.nix:2822` passes
`inputs = if commitBound ? ${n} then realInputs else inputs`, and any explicit
commit-bound entry uses `realInputs` the same way. `commitBound` is the exempt
table (§5), one file read by both flake and guard.

Not reached by the shadow:

- `microvm-template` takes `nixarchyVm = self.packages.…nixarchy-vm`
  (`flake.nix:2750`), built with the real `self` (`flake.nix:1133`). It
  changes to `callPackage ./pkgs/microvm.nix { inherit (checkInputs) self; }`,
  the way the test already builds its `dirtyVm` (`tests/microvm-template.nix:50`).
- Checks built from `self.nixosConfigurations.{vm,reference}` (coexistence,
  generate-config-surface, graphics-*, etc-sysctl and others at
  `flake.nix:2641-2784`), and `options-*`, which reads
  `inputs.self.nixosConfigurations.vm` (`tests/options.nix:643`; `self // {…}`
  keeps the real configurations). Most read attributes, not `/etc`, and may not
  move. **Decided remedy for each one the guard reports:** it gets the same
  configuration built from `checkInputs` (the plan factors the
  `nixosConfigurations` block at `flake.nix:1449` into a function of `inputs`
  if more than one needs it, and `checkInputs.self.nixosConfigurations` is set
  from it). Exemption is only for the provenance reasons in §5. The measured
  list says which checks need the remedy; it does not choose the remedy.

### 5. Exempt, by name, each with its reason

One file, `data/commit-bound-checks.nix` (`{ <check> = "<reason>"; }`), read
by `flake.nix` (real inputs, above) and by the guard:

| check | why it carries the commit |
|---|---|
| `vm-toplevel`, `reference-toplevel`, `reference-unencrypted-toplevel` (`flake.nix:2783`) | the machine a user gets, `/etc/nixarchy/version` included |
| `install`, `install-encrypted`, `free-space`, `installer-refusal` | collect every input's `outPath` (`tests/install.nix:64-68`) and must seed what the installed machine evaluates |
| ISO checks (`iso-source`, `iso-wifi`, `iso-budget`, `install-iso-net`) | `installer/cd.nix` `inputSources` |
| `installer-lock` | reads `flake-template`, which pins `self.rev` (`installer/mkFlake.nix:22`) |
| `nixarchy-options` | the one place the real rev is asserted (below) |

The guard's first measured run may add an entry only for one of these reasons,
naming its carrier.

### 6. Where the real rev is still asserted

`tests/nixarchy-options.nix` gains two assertions against
`self.nixosConfigurations.reference` (real `self`): every declaration this
repository owns (a URL under `github.com/olafkfreund/nixarchy/blob/`; flatsnap's
and nixpkgs' are left alone, `modules/nixos.nix:304-316`) contains
`/blob/${self.rev or "main"}/`, and there is at least one such declaration (so
an empty match cannot pass); `etc."nixarchy/version".text`
equals `import ./modules/revision.nix self`'s line; and the Mode A half of the
same test adds `nixarchy/version` to `hasOn`/`hasOff`.

### 7. The guard: `.github/scripts/commit-independent.sh`

1. Refuses on a dirty tree. `git worktree add --detach <scratch> HEAD`, under
   `${RUNNER_TEMP:-/mnt/data/vmtest}`; refuses if that directory does not exist
   rather than falling back to `/tmp` (§5).
2. Names: its arguments, or every `checks.x86_64-linux` attribute minus the
   names in `data/commit-bound-checks.nix`. An exempt name that is no longer a
   check fails (§4: a hand-kept list must not fail open).
3. Evaluates each check's `outPath` one process at a time in the scratch tree
   (memory: `generate-config-surface` alone peaks at 11.6 GB,
   `already-proven.sh:97-102`). `out=$(nix eval …) || fail`: an unevaluable
   check is a failure, never a pass (§5, `set -e` and `$(…)`).
4. Commits a probe in the scratch tree: a new tracked file `.commit-probe`,
   `GIT_COMMITTER_DATE` two days after `HEAD`'s, so `rev`, `lastModifiedDate`'s
   day, `narHash` and the source `outPath` all differ, and nothing the build
   reads does.
5. Evaluates again, prints every check whose outPath moved, exits 1 if any did.
   A floor like `already-proven.sh:150-165`: compared count must equal the
   requested count.
6. Removes the worktree in an EXIT trap on a global (§5).

Wired as a new `nightly.yml` job, added to `report`'s `needs` (§4's
`reinstall-vm` lesson), with its own branch in the report's title chain
(`nightly.yml:630-667`) and no `installer` label (`nightly.yml:694`): alone, its
failure would otherwise be filed as "the install checks are failing", the #236
shape that chain exists to avoid. This is a CI-workflow change, so the PR proposes it for
a human to merge (§11). Nightly, not per PR: a leak costs cache hits, never a
wrong result, and two evaluations of every check is the expensive row in §6.

## Coexistence

`/etc/nixarchy/version` is a new `environment.etc` entry in nixarchy's own
`/etc/nixarchy/` namespace, beside `nixarchy/flake` and `options.json`; nothing
in nixpkgs or a user's config is known to write it, and an `environment.etc`
clash fails evaluation loudly rather than shadowing. The standalone-HM
`~/.config/nixarchy/version` is new under nixarchy's own directory. No merged
env (`systemPackages`, `hardware.graphics`) gains or loses a file, so no
`tests/coexistence` fixture can fail on it; none is added (§14: a fixture that
cannot fail is worse than none).

## Alternatives rejected

- **Rewrite catalogue URLs to `main`.** Points old machines at the wrong source
  (intent Q2).
- **A top-level `rev` field in `options.json`.** The picker's `to_entries[]`
  would list it as an option; every reader and the release asset would need
  migrating.
- **A tiny `nixarchy-version` package outside `omarchy`.** Shadows a file inside
  `omarchy`'s bin in `system.path`, resolved silently by priority (§14's quiet
  failure mode).
- **An internal option for the rev.** Needs every test fixture to set it;
  `checkInputs` reaches all 27 sites and every new check in one binding.
- **Guard as a flake check with two fake `self`s.** Misses `self.outPath` and
  `narHash`, the carriers intent Q5 names.
- **Guard on every PR.** Two full evaluations per run for an effect that only
  costs cache hits.

## Risks

- **Every installed machine's `omarchy` changes once** (the splice goes). One
  rebuild, then stable. Release notes say `nixarchy-version` now reads
  `/etc/nixarchy/version`.
- **A machine built from a dirty checkout** still prints `-dirty`
  (`dirtyShortRev`, unchanged logic).
- **Behaviour checks no longer test the exact `/etc` bytes a user gets**; the
  version line and catalogue URLs are asserted in `nixarchy-options` against
  the real `self`, and the real toplevels still build.
- **The offline install** (`tests/installer-lock.nix`'s history): the
  installed flake must evaluate the same `omarchy` the installer seeded. That
  gets easier, since `omarchy` no longer depends on `lastModified`; the
  toplevel still does, as today, and `install` still proves rebuild-builds-nothing.
- **Unknown carriers** (microvm guests in `packages.microvm-*`, `stableVm`,
  `self.outPath` in a fixture): the guard's first run lists them; the plan
  resolves each.
- **Guard cost in the nightly** is unmeasured; the plan's first step measures it
  locally and states it.

## Verification

- **Measure first.** Run the guard on today's `main` (VM-tier gate, §6: no
  self-hosted runner busy). Expected red, listing at least `omarchy`, `session`,
  `coexist`, `integration`, `plugin`, `microvm-template`. That output is the
  guard's §1 failing proof and the input to the exempt list.
- **Guard green after the change**, same command.
- **Guard break:** restore `--replace-fail '@nixarchyrev@' '${nixarchyRev}'`
  (and its arguments) in `pkgs/omarchy/default.nix` → guard red naming
  `omarchy` and its dependants. Second break: remove `nixosModules` from
  `checkInputs.self` → red naming `session`. The guard refuses a dirty tree, so
  each break is a throwaway commit in a `git worktree add --detach` scratch
  tree (§5), shown with `git show --stat` before the run, and the captured red
  must be the moved-outPath list, not the dirty-tree refusal (§1).
- **Guard's own failure modes:** an exempt name that is not a check → exit 1;
  a check that does not evaluate (temporary `throw`) → exit 1, not "nothing
  moved".
- **`omarchy` self-check:** drop the file read from `nixarchy-version` → the
  package build fails on the XDG fixture.
- **`nixarchy-options`:** hard-code `rev = "main"` at `modules/nixos.nix:284` →
  red; write a wrong date into the version line → red; drop the `cfg.enable`
  gate's coverage of `nixarchy/version` → Mode A half red.
- **Untouched and green:** `channel`, `verify-runs`, `installer-lock`,
  `cache-budget`, `options-*`, statix, deadnix, `nix fmt -- --ci`, and
  `.github/scripts/readme-counts.sh`.
