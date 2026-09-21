---
status: approved
issue: 801
spec: spec/2026-09-20-801-retire-box-cli.md
---

# Plan: retire the `nixarchy box` CLI

Branch `feat/801-retire-box-cli`, already carrying the spec. One commit per
step, each subject a full sentence (AGENTS.md §8). A deviation updates this
file in the same commit as the code.

## Approved decisions

Copied from the spec so this file stands alone.

- **Nothing is blocked, and nothing is written in `nixarchy-distrobox`.**
  `promote` landed at `dd9e89c`, the rev `flake.nix:243` already pins; the
  `--check` gate was never needed because `modules/apps.nix:704` gates the
  Boxes row on `nixarchy-plugin --enabled nixarchy.distrobox` and
  `nixarchy box --check` has zero callers; nothing consumes
  `nixarchy box list` programmatically.
- **What goes:** `pkgs/box.nix`, the `nixarchy-box` package
  (`flake.nix:973`) and its `nixarchyBox` argument (`flake.nix:2248`), the
  `box` verb at `modules/apps.nix:3077`, README's two rows and the CLI half of
  `docs/manual/boxes.md`.
- **What stays:** `data/box-templates.nix` as the single source,
  `services.boxes.machines`, and the Boxes menu row — which is already the
  panel. The row's `"box"` alias at `modules/apps.nix:708` stays: it is how a
  user searching for "box" finds the panel.
- **The two checks are retargeted, not deleted.** Losing coverage as a side
  effect of a deletion is not a decision anyone made.
- **`nixarchy box` prints a pointer** for one release rather than
  "unknown verb".
- **The `build.yml` half is merged by a human** (§4, §11).

## Steps

**1. Retarget the checks first, before anything is deleted.** Coverage must
never lapse, and doing this first means step 2 is a deletion against a suite
that already tests the replacement.

- `tests/box-boot.nix` — `:95` runs `nixarchy box create`; it runs
  `distrobox assemble` against the generated
  `/etc/nixarchy/box-templates.ini` instead.
- `tests/box-template.nix` — the catalogue assertions stay; the
  `${nixarchyBox}/bin/nixarchy-box` grep at `:92` goes, with a comment saying
  why it has no panel equivalent (the plugin is QML and resolves `distrobox`
  through `PATH` by construction).

→ verify by both checks passing, **and by proving each fails** (§1): point the
retargeted path at a template name that does not exist and capture the output.
Both failing outputs go in the PR. Prove the break landed with `git diff`
before believing a red result.

**Deviation, recorded with the code that caused it.** `flake.nix:2248`
(`nixarchyBox = …`) moved from step 2 into step 1. Dropping the `nixarchyBox`
parameter from `tests/box-template.nix` makes the call site pass an argument
the function no longer accepts, so the tree does not evaluate between the two
steps. Step 2 keeps the rest of its flake work; only this line moved.

Two container-name notes the retarget forced, since they are behaviour and not
style. `/etc/nixarchy/box-templates.ini` is keyed by TEMPLATE name, where
`nixarchy box create` stitched on a header naming the BOX — so the container
`box-boot` creates is now `archlinux`, not `scratch`. And `--name` is required:
without it `distrobox-assemble` would create every template in the catalogue.

**2. Remove the CLI.** `pkgs/box.nix` deleted; `nixarchy-box` and the
`nixarchyBox` argument out of `flake.nix`; `modules/apps.nix:3077` becomes a
pointer rather than an exec:

```
box) echo "nixarchy box is retired -- boxes live in the Distrobox panel" \
          "(Super+Alt+D, or the Boxes row in the menu)." >&2; exit 1 ;;
```

→ verify by `nix flake show` no longer listing `nixarchy-box`, and by running
`nixarchy box` to read the message.

**Deviation.** This step originally said `nix build .#nixarchy`. There is no
such attribute and never was: the dispatcher is a `writeShellApplication`
inside `modules/apps.nix`'s `systemPackages`, not a flake package, so the
command fails with *"flake … does not provide attribute"* whatever the state
of the tree. Replaced by two things that do answer the question —
`checks.menu-verbs`, which evaluates the module and builds the menu, and
building the `systemPackages` entry out of `nixosConfigurations.reference` to
run it. Both done; `nixarchy box` prints the pointer and exits 1.

**3. `tests/menu-verbs.nix`.** `:135` knows the box rows go through
`nixarchy box <verb>`. It is updated with them, in the same commit as step 2 —
a check that describes a command which no longer exists is the stale assertion
§1 warns about.

→ verify by `checks.menu-verbs` passing.

**4. The documentation.** README `:47` and `:460`, `docs/manual/boxes.md`, and
`docs/index.md` if it names the command. Each says what replaces it — the
panel, Super+Alt+D — rather than simply dropping the sentence.

→ verify by `grep -rn "nixarchy box" README.md docs/` returning only
historical references, and by `readme-counts.sh` staying green (removing rows
moves counts, and that guard refuses on a number it cannot spell).

**5. `tests/AGENTS.md`: the coverage this trades away.** The old checks
exercised a script this repo owns; the new ones exercise a plugin pinned by
rev, so a plugin bump could change the create path with nothing here going red.
A documented hole gets tested by a human; an undocumented one gets tested by a
user (§3).

→ verify by the sentence existing, naming the gap rather than the fix.

**6. The `build.yml` edit, for a human to merge.** `box-template` and
`box-boot` are claimed at `:1293` and `:1503` — `generated-checks.sh` lists
neither, verified. If the retargeted checks keep their names this is only the
comment above each step; if they are renamed it is the names too.

→ verify by saying so in the PR and **not merging it myself**.

## Tests

```
nix build .#checks.x86_64-linux.box-template --print-build-logs
nix build .#checks.x86_64-linux.box-boot --print-build-logs
nix build .#checks.x86_64-linux.menu-verbs
nix build .#nixarchy
.github/scripts/readme-counts.sh
nix fmt -- --ci && nix run --inputs-from . nixpkgs#statix -- check . \
  && nix run --inputs-from . nixpkgs#deadnix -- --fail .
```

The lint trio is run over **`.`, not the changed files** — #829 was `main`
going red because the new line was fine and its neighbours were not, and
linting only what you wrote cannot see that.

By hand, in a booted `.#vm`: Super+Alt+D opens the panel, and a box is created
from a nixarchy template through it. That is the thing the CLI used to do, and
no automated layer here reaches it.

`box-boot` needs `/dev/kvm` and is one of the expensive rows in §6's table.
Check `gh run list` before starting it locally, and do not start one while an
install job is in flight — including one your own merge has just triggered.

## Rollback

`git revert` the merge. The CLI comes back whole, since the change is a
deletion plus two retargeted tests; nothing migrates state and nothing is
written outside the repo.

The one thing a revert does not undo is a user who has already learned the
panel — which is the intended direction, not a risk.
