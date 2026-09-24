---
status: draft
issue: 959
spec: spec/2026-09-24-959-shadowed-plugins.md
---

# Plan: doctor names a plugin directory that shadows a shipped one

## The approved decisions, carried over

Self-contained; nothing here needs the intent or spec open.

1. **It surfaces in `nixarchy doctor`, not a desktop notification.** Doctor is
   testable cheaply -- `tests/doctor-graphics.nix` runs it in a `runCommand`
   against a faked environment and asserts on the transcript -- and is already
   sectioned. The accepted weakness: nothing runs doctor automatically, so this
   makes the problem *diagnosable*, not *announced*.

2. **Report, do not decide.** Same `origin` is necessary and insufficient: p620's
   `olafkfreund.github-actions` clone is same-origin and **28 commits ahead**,
   entirely deliberate. Doctor names the directory, both commits, and which of
   ahead / behind / equal / unrelated applies, showing the fix only for
   **behind** or **unrelated**. A shallow clone that cannot answer reports
   unrelated -- it asks a human rather than staying quiet.

3. **The manifest change is a DEPENDENCY, not a separate issue**, and this is
   why the approved blast radius includes activation. Doctor deliberately
   inspects the live system rather than evaluating a flake -- its header states
   that, because it must work *before* nixarchy is an input. So it learns the
   declared set from `~/.config/omarchy/plugins/.nixarchy-managed`, which today
   lists what activation **linked** and therefore omits exactly the shadowed ids
   this issue is about.

4. **Nothing is moved, renamed or deleted on the user's behalf.** The existing
   "your own directory, not replacing it" behaviour stays.

## Steps

1. **`modules/home.nix:1110-1116`** -- on the shadowed branch, write the id to
   `${staging}` with a leading `!`:

   ```sh
   if [ -e "${dir}/$id" ] && [ ! -L "${dir}/$id" ]; then
     echo "nixarchy: ${dir}/$id is your own directory, not replacing it"
     echo "!$id" >> "${staging}"
   else
   ```

   A marker in the same file, not a second file, so the removal loop below keeps
   working unchanged: it does `grep -qxF "$stale"` against exact lines, so `!id`
   never matches a bare `id` and a shadowed plugin is never removed -- which is
   already what that branch wants.
   → verify by `checks.options`, step 4.

2. **`modules/home.nix:1130-1132`** -- the comment above the tail says *"The
   manifest exists only while this module planted something: an empty file in a
   user's plugins directory means nothing to them."* That is no longer true:
   with markers it exists while this module **declared** something, which
   includes a machine where every declared plugin is shadowed. Update the
   comment to say so.
   → verify by reading it back; no build effect.

   The `[ ! -s "${staging}" ]` branch is unchanged and still correct: nothing
   declared still means no manifest.

3. **`flake.nix:540-559`** -- add `git` to `nixarchy-doctor`'s `runtimeInputs`.
   It is a `writeShellApplication`, so the PATH is strict and an undeclared
   `git` is a runtime failure no build catches. That trap is recorded twice in
   this very list, on `libva-utils` and `glibc`; this is the third.
   → verify by step 5's fixture exercising the ahead/behind path.

4. **`pkgs/doctor.sh`** -- a **Plugins** section, its first. It reads
   `$config_home/omarchy/plugins/.nixarchy-managed`; for every line beginning
   `!`, the directory at that id is shadowing a declared plugin. Per id:

   | state | output |
   |---|---|
   | not a git clone | one line: this is yours, nixarchy is not managing it. No advice. |
   | clone, different origin | same. |
   | clone, same origin, **equal** | a note: it will silently stop tracking at the next pin bump |
   | clone, same origin, **ahead** | says so; nixarchy's copy is older. No advice to move it. |
   | clone, same origin, **behind or unrelated** | the finding: both commits, and `mv` aside + restart `home-manager-<user>` |

   Ahead/behind by `git merge-base --is-ancestor` in both directions, no
   network. **With no manifest, or no `!` lines, the section prints nothing** --
   a machine that has never had nixarchy, which is doctor's primary audience,
   must see no new output at all.
   → verify by step 5.

5. **`tests/doctor-plugins.nix`** -- modelled on `tests/doctor-graphics.nix`:
   a faked `$XDG_CONFIG_HOME` with a manifest and a plugins directory in each
   of the five states, doctor run against each, transcript asserted. Plus a
   sixth case with **no manifest**, asserting the section is silent.

   **Section 1:** each case seen failing with the finding removed, and that
   output in the PR. The trap to avoid: asserting that the section *printed
   something*, which a bare `say` satisfies. Assert the commit strings.

6. **Raise, do not wire, the workflow entry.** A `checks.doctor-plugins` entry
   must be named by a workflow that triggers on pull requests, or the coverage
   gate fails -- and that workflow edit is a CI-gate change needing a human
   (section 4, section 11). Add the check to `flake.nix`, say in the PR that it
   needs a workflow line, and let a human add it.

7. **`tests/AGENTS.md`** -- record what this cannot reach: doctor is not run
   automatically, so a shadowed plugin is found when someone asks, not when it
   happens.

## Tests

| command | expected |
|---|---|
| `nix build .#checks.x86_64-linux.doctor-plugins` | passes; each state asserted |
| `nix build .#checks.x86_64-linux.options` | passes -- Mode A both ways, and the manifest gains `!` lines only where a directory shadows |
| `nix build .#checks.x86_64-linux.doctor-graphics` | still passes -- same script, and the new section must not disturb its transcript |
| `nix build .#nixarchy-doctor` | builds with `git` declared |
| `nix fmt -- --ci`, statix, deadnix | clean |

Section 1 evidence to capture: `doctor-plugins` red with step 4's comparison
removed, green with it restored.

By hand afterwards on **p620 and razer**, which between them have four of the
five states live today -- including *ahead*, which no fixture would have
invented.

Queue check before any heavy build (`gh run list`), per section 6.

## Rollback

`git revert`. The manifest loses its `!` lines on the next activation, which is
the file being rewritten as it always is; nothing reads them once doctor's
section is gone. No user directory is touched in either direction, at any point,
which is the property that makes this safe to revert at all.
