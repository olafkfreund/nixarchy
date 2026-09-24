---
status: draft
issue: 974
intent: intent/2026-09-24-974-ghtui-runtimedeps.md
---

# Spec: the GitHub panel's runtime tools come from the panel

## The intent's open questions, decided

All three taken as my leans, since the approval came without a pick.

**1. Bind it beside `githubActions`, not inline.** The binding goes where the
`cp -r` that loses `passthru` already is (`modules/home.nix:306`), because those
two facts only make sense together: *the copy drops `passthru`, therefore the
list is read from the input.* Inline at the plugin entry, four hundred lines
away, the expression looks like a mistake -- it names the same package the entry
already has as `src`, by a longer route, for no visible reason.

**2. gitlab and menu follow later, separately.** `gitlab-pipelines` cannot
follow at all until its own panel declares `runtimeDeps`, which is another
repository and not ours to file (section 11). `nixarchy.menu` landed hours ago
in #946 and has the longest list. Changing three entries to demonstrate a
pattern is scope the reviewer did not ask for.

**3. No check comparing the two lists.** After this change there is one list.
A check would assert that an expression equals itself, which is the shape
section 1 calls a green light.

## Design

```nix
githubActions = pkgs.runCommand "nixarchy-ghtui" { } ''
  cp -r ${ghtui} $out
  ...
'';

# `cp -r` above makes a new derivation, and a new derivation has no passthru --
# so the panel's own runtimeDeps cannot be read off `githubActions`, only off
# the input. Bound here rather than at the plugin entry because the reason and
# the cause are the same two lines.
githubActionsDeps = ghtui.runtimeDeps;
```

with `ghtui` itself bound once to
`inputs.nixarchy-ghtui.packages.${pkgs.stdenv.hostPlatform.system}.default`,
which the `runCommand` already interpolates in full.

The plugin entry then reads:

```nix
github = {
  id = "olafkfreund.github-actions";
  src = githubActions;
  packages = githubActionsDeps;
};
```

**The pin bump is part of this change.** `runtimeDeps` does not exist at
`4f51f7f`; it arrived in nixarchy-ghtui#37, merged 19:25 on 2026-09-24. Verified
against the bumped input rather than assumed:

```
$ nix eval ... .default.runtimeDeps
gh python3 xdg-utils
```

-- the same three the hand-written list names, so this change is behaviour-
preserving today and stops being a hand-written list tomorrow.

## Alternatives rejected

| | why not |
|---|---|
| Read from `githubActions` | It is a `runCommand` copy; `passthru` is gone. This is the obvious fix and it silently yields an error, not a list. |
| Inline at the plugin entry | Puts a long, non-obvious expression 400 lines from the reason it exists. |
| Keep the list and add a check that it matches | After this there is one list. The check would compare an expression to itself. |
| Stop wrapping in a `runCommand` | The wrapper exists to add `menu.managed` and a `LICENSE`; removing it is a different change with its own reasoning to unpick. |
| Do all three panels now | gitlab cannot (upstream has not declared it); menu just landed. Scope. |

## Risks

- **Default-plugin fixtures.** The bus records that an ungated default breaks
  `noDefaultsHome` in `tests/options.nix` and the `machine` node's
  `defaultPlugins` block in `tests/plugin.nix` -- in different files, with
  neither failure naming the plugin. This entry is **not** new and **not**
  ungated-by-change: only its `packages` expression moves, so neither fixture
  should notice. That is a prediction, and `checks.options` is what tests it.
- **The pin moves with the code.** A bump and a behaviour change in one commit
  is harder to bisect. Accepted because the attribute does not exist at the old
  pin, so they cannot be separated.
- **`runtimeDeps` is someone else's attribute.** If a future ghtui drops or
  renames it, evaluation fails -- loudly, at build time, naming the attribute.
  That is the right failure and better than the current silent staleness.

## Verification

- **`checks.options`**, which asserts every option in both states and is where a
  default plugin's packages are visible. Section 1: the case must go red with
  the binding replaced by a wrong list, and that output in the PR.
- **`nix eval`** of the bound attribute, showing the three packages, so the
  PR records what the list actually resolved to rather than asserting it did.
- **`checks.plugin`** is the second fixture the bus names. It boots a VM; if the
  queue does not allow it, the PR says so rather than implying it ran.
- **What no check reaches:** whether the panel's scripts actually invoke only
  those three. That is the panel's claim about itself, and trusting it is the
  point of the change.
