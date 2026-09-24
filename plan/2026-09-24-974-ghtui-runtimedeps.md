---
status: approved
issue: 974
spec: spec/2026-09-24-974-ghtui-runtimedeps.md
---

# Plan: the GitHub panel's runtime tools come from the panel

## The approved decisions, carried over

1. **Bind beside `githubActions`** (`modules/home.nix:306`), not inline at the
   plugin entry 1,550 lines away. The `cp -r` there makes a new derivation,
   which has no `passthru`, so the list cannot come from `githubActions` -- only
   from the input. Cause and reason are the same two lines.
2. **The pin bump is part of this change.** `runtimeDeps` does not exist at
   `4f51f7f`; it arrived in nixarchy-ghtui#37, merged 19:25 on 2026-09-24.
   Verified: it resolves to `gh python3 xdg-utils`, the same three the
   hand-written list names -- so this is behaviour-preserving today.
3. **gitlab and menu do not follow here.** `gitlab-pipelines` cannot until its
   own panel declares the attribute (another repository, section 11);
   `nixarchy.menu` landed hours ago in #946.
4. **No check comparing the lists**: after this there is one list, and a check
   would assert an expression equals itself.

## Steps

1. **`modules/home.nix:306`** -- bind the input's package once, and its
   `runtimeDeps` beside it, with the reason at the line.
   → verify by step 3.
2. **`modules/home.nix`, the `github` plugin entry** -- `packages =
   githubActionsDeps;` replacing the three-element literal.
   → verify by step 3.
3. **`checks.options`**, seen failing first: replace the binding with a wrong
   list, watch it go red, restore it, watch it pass. That output in the PR.

## Tests

| command | expected |
|---|---|
| `nix build .#checks.x86_64-linux.options` | passes |
| `nix eval` of the bound attribute | prints `gh python3 xdg-utils` |
| `nix fmt -- --ci`, statix, deadnix | clean |
| `nix build .#checks.x86_64-linux.plugin` | the second fixture the bus names; if the queue does not allow it, say so in the PR rather than imply it ran |

## Rollback

`git revert`. The literal list returns and the pin goes back, together -- they
cannot be separated, because the attribute does not exist at the old pin.
