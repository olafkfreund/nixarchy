---
status: draft
issue: 1205
intent: intent/2026-10-06-1205-python313-inline-script.md
---

# Spec: stable machines can build omarchy again

## Design

### 1. The menu check moves into its own file

`pkgs/omarchy/default.nix:1174-1234` runs `${python3}/bin/python3 -c '<code>'
$menu $out/share/omarchy/bin/omarchy-default-agent`. The code moves verbatim,
dedented, into `pkgs/omarchy/check-menu.py`, and the call becomes:

```nix
${python3}/bin/python3 ${./check-menu.py} $menu $out/share/omarchy/bin/omarchy-default-agent
```

The code has no Nix interpolation (checked: the only `${` in the block is the
`python3` path itself), so it moves without change. The comment above the
call stays, and gains one line saying why the script is a file: inline `-c`
code inside an indented Nix string depends on Python 3.14's automatic dedent,
and 3.13 rejects it (#1205).

Unstable is affected only through the omarchy derivation's own inputs. The
script's behaviour is identical: same code, same arguments.

### 2. The guard: a static check, plus the weekly build

`checks.inline-python` (new, `tests/inline-python.nix`), shaped like
`tests/grep-q-pipefail.nix`: it scans the tree's `.nix` and `.sh` files for a
`python3 -c '` (or `python -c '`) that ends its line and whose next line
starts with whitespace, and fails naming file and line. Every current site
except the one fixed here is flush-left, so the check starts green with no
allowlist. It is evaluation-cheap, so it runs on every PR through the
generated checks.

A per-PR build of omarchy against 26.05 is rejected (see below). #1199's
weekly `stable-session` builds omarchy against 26.05 anyway, and catches any
other 3.14-only construct within a week.

### 3. The hotfix: `v4.0.4-2` from `release`

`release` (`v4.0.4-1`) has an older, shorter version of the same script
(`:1160-1212`, without the #949 agent-row check), so the fix is applied to it
directly rather than cherry-picked:

1. `git switch -c hotfix/1205 origin/release`.
2. The same change as 1, against release's script: release's code moves to
   `pkgs/omarchy/check-menu.py` and the call passes the arguments release's
   script reads.
3. Verify on that branch: omarchy builds against nixos-26.05 and against the
   branch's own nixpkgs (the commands are under Verification).
4. Commit, push the branch. **Stop and ask the maintainer** before tagging.
5. On the go-ahead: `git tag -a v4.0.4-2 -m v4.0.4-2` at the branch head and
   push the tag. `release.yml` (the tag's own copy) builds the ISOs, publishes
   them, and fast-forwards `release`. The tag is not on main, so the
   behind-main guard lets it through.
6. Merge back: a PR into `main` from a branch with
   `git merge -s ours v4.0.4-2`, merged with **Create a merge commit**, so
   `release` is an ancestor of `main` again.

The hotfix carries only this fix. `v4.0.4-1` predates #792, so it has no
herdr bug to fix.

### 4. Back to #1199

With 1 on `main`, #1199 step 5's `stable-session` build is re-run. If it stops
on another stable-only failure, that gets its own issue.

## Alternatives rejected

- **Flush-left code inside the Nix string.** That works, but flush-left lines
  change the minimum indentation of the whole `installPhase` string, so every
  other line's leading whitespace changes too. It is also fragile: the next
  edit re-indents it.
- **`python3 - <<'EOF'` heredoc.** It has the same indentation question in a
  different form, and it still embeds a 60-line program in a shell string.
- **Pin a Python 3.14 for this script.** That would mean a second interpreter
  in the build closure of every stable machine, to keep a style choice.
- **A per-PR build of omarchy against 26.05.** Uncached on stable, and every
  dependency change rebuilds it. The static check covers this bug class for
  almost nothing; the weekly build covers the rest.
- **Cherry-pick main's fix onto `release`.** The scripts differ, so the
  cherry-pick would conflict or carry the #949 check onto a release without
  the menu rows it checks.

## Risks

- **The script reads paths relative to the build.** It does not: it opens
  `sys.argv[1]` and `sys.argv[2]`, which the call passes absolutely.
- **More stable-only failures behind this one** (intent question 3). The
  hotfix fixes only this one, and the hotfix verification builds the omarchy
  package against 26.05, not the whole stable system. If the release has
  another stable-only build failure, `v4.0.4-2` will not fix it. The
  verification step should also build a stable system toplevel from the
  hotfix branch, to find that out before the tag.
- **A failed hotfix release.** `release.yml` publishes, then moves `release`.
  If it fails before the move, `release` is unchanged and users keep
  `v4.0.4-1`. That is no worse than today.
- **Forgetting the merge-back.** Then the next normal release cannot move
  `release`. #1199's weekly issue warns about it once #1199 lands, but #1199
  is not merged yet, so the merge-back is a numbered step here and in the plan.

## Verification

- `main`: `nix build .#packages.x86_64-linux.omarchy` (unstable) passes.
- `main`: omarchy built against nixos-26.05 passes:
  `nix build --impure --expr 'let f = builtins.getFlake (toString ./.); in (import f.inputs.nixpkgs-stable { system = "x86_64-linux"; overlays = [ f.overlays.default ]; }).omarchy'`.
- `main`: `nix build .#checks.x86_64-linux.inline-python` passes. With the
  old inline block restored, it fails naming `pkgs/omarchy/default.nix`.
- Hotfix branch: the same two omarchy builds pass, and a stable system
  toplevel builds (`stableVm` on `release` uses unstable inputs, so this is
  an equivalent `--impure` expression the plan spells out).
- After the tag: the release job is green, `release` points at `v4.0.4-2`,
  and after the merge-back
  `git merge-base --is-ancestor origin/release origin/main` is true.
