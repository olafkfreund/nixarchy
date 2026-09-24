---
status: draft
issue: 974
author: olafkfreund
---

# Intent: the panel says what it needs, and we stop repeating it

## Problem

`modules/home.nix:1857-1859` lists the GitHub Actions panel's runtime tools by
hand:

```nix
github = {
  id = "olafkfreund.github-actions";
  src = githubActions;
  packages = [ pkgs.gh pkgs.python3 pkgs.xdg-utils ];
};
```

The panel now declares the same list itself. nixarchy-ghtui#37 (for #32) added
`passthru.runtimeDeps = [ gh python3 xdg-utils ]`, and **that PR merged at 19:25
today** -- after the issue was filed saying this was blocked on it. Verified
against the bumped input rather than taken on trust:

```
$ nix eval ... inputs.nixarchy-ghtui.packages.x86_64-linux.default.runtimeDeps
gh python3 xdg-utils
```

Two copies of one list, and the panel's is the authoritative one: it knows what
its own scripts invoke. Ours goes stale the moment the panel starts calling
something new, and the failure is section 7's `runtimeInputs` shape -- a command
that is not there reads as a wrong answer rather than a missing one.

## What reading the code adds

**The obvious one-line fix does not work, and the issue says why.** It cannot be
read off `githubActions` (`modules/home.nix:306`), because that is a
`runCommand` that copies the package with `cp -r`:

```nix
githubActions = pkgs.runCommand "nixarchy-ghtui" { } ''
  cp -r ${inputs.nixarchy-ghtui.packages...default} $out
```

A copy is a new derivation and **drops `passthru`**. So the list has to come
from the input directly, not from the `src` the plugin entry already names --
which means the entry references the same package twice, by two routes, and a
reader has to understand why.

**And this is not one list, it is a pattern.** The same shape sits two entries
up at `:1846-1848` -- `olafkfreund.gitlab-pipelines` with `glab python3
xdg-utils`, wrapped by its own `gitlabPipelines` `runCommand` -- and again at
`:1822-1830` for `nixarchy.menu`, which lists eight. The issue mentions
nixarchy-gltui as having the same pattern. So whatever is decided here is a
decision about **how a nixarchy plugin declares its runtime tools**, not about
one entry.

## Proposed outcome

- The GitHub panel's tools come from the panel, so adding one upstream needs no
  change here and cannot be forgotten.
- The reason the list is read from the input rather than from `src` is written
  at the line, because it is not obvious and the obvious thing is wrong.
- Whatever shape is chosen is one the other panels can adopt, rather than a
  one-off that makes the next entry look inconsistent.

## Affected users and systems

- `modules/home.nix`'s default plugin set, and the `nixarchy-ghtui` input pin.
- Anyone whose GitHub panel calls a tool the panel declares and we do not --
  today, nobody, because the lists agree. That is what makes this maintenance
  rather than a bug.

## Constraints

- **The pin bump is part of this change**, not a prerequisite someone else does:
  the attribute does not exist at our current pin (`4f51f7f`).
- **`checks.options` must see both states.** A default plugin's packages are
  exactly what the all-defaults-off fixtures in `tests/options.nix` and
  `tests/plugin.nix` are sensitive to -- the bus records an ungated default
  breaking both, in different files, with neither failure naming the plugin.
- **Not a refactor of the other two entries** unless that is decided
  deliberately. Changing three entries in one PR to prove a pattern is scope the
  reviewer did not ask for.

## Open questions

1. **Read it inline, or bind it once?** Inline is
   `inputs.nixarchy-ghtui.packages.${system}.default.runtimeDeps`, which is
   long, repeats what `githubActions` already interpolates, and puts the reason
   at the one place it is needed. A `let` binding beside `githubActions` reads
   better and separates the reason from the use. I lean to **binding it beside
   `githubActions`**, because that is where the `cp -r` that loses `passthru`
   lives, and the two facts belong together.

2. **Do gitlab and menu follow now or later?** `gitlab-pipelines` cannot until
   its panel declares `runtimeDeps` -- that is upstream of us in another
   repository and not ours to file (section 11). `nixarchy.menu` just landed
   (#946) and its list is longest. I lean to **later, and separately**, with
   this PR naming the pattern so the next one is a smaller argument.

3. **Should a check assert the two agree?** Today they do. A check comparing our
   list against `runtimeDeps` would be the comparison section 4 asks for -- but
   after this change there is only one list, so there is nothing to compare, and
   a check would be asserting that an expression equals itself.

## Not in scope

- `nixarchy-gltui`, which the issue notes has the same pattern and has not
  ported the change.
- Anything about what the panels actually invoke at runtime.
