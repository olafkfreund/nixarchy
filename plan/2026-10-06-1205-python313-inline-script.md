---
status: approved
issue: 1205
spec: spec/2026-10-06-1205-python313-inline-script.md
---

# Plan: stable machines can build omarchy again

## Approved decisions (from the spec)

- The menu-check Python in `pkgs/omarchy/default.nix` moves verbatim and
  dedented into `pkgs/omarchy/check-menu.py`, and is called as
  `${python3}/bin/python3 ${./check-menu.py} <same args>`. Cause: an indented
  `python3 -c` program relies on Python 3.14's automatic dedent, and 26.05
  ships 3.13.
- New `checks.inline-python` (static, every PR) fails on any `python3 -c '`
  or `python -c '` that ends a line and whose next line is indented, in
  `.nix` and `.sh` files.
- Hotfix `v4.0.4-2`: the same fix applied to `release`'s shorter script, on
  `hotfix/1205` from `origin/release`. It is verified including a whole stable
  toplevel. **The tag is pushed only after the maintainer says so at that
  moment.** It is merged back into `main` with `git merge -s ours` and a merge
  commit. It carries only this fix.
- Afterwards, #1199 step 5's `stable-session` build is re-run.

## Steps

### On `main` (this branch, `fix/1205-python313-inline-script`)

1. **`pkgs/omarchy/check-menu.py` (new) and `pkgs/omarchy/default.nix:1170-1234`.**
   Move the code between `-c '` (`:1174`) and the closing `'` (`:1234`) into
   the new file, dedented by its common indent, with no other change. Replace
   the call with
   `${python3}/bin/python3 ${./check-menu.py} $menu $out/share/omarchy/bin/omarchy-default-agent`.
   Add one line to the comment above it: the script is a file because
   inline `-c` code inside an indented Nix string needs Python 3.14's dedent
   (#1205).
   → verify by building omarchy for unstable,
   `nix build --no-link .#packages.x86_64-linux.omarchy`, and for 26.05,
   `nix build --no-link --impure --expr 'let f = builtins.getFlake (toString ./.); in (import f.inputs.nixpkgs-stable { system = "x86_64-linux"; overlays = [ f.overlays.default ]; }).omarchy'`.
   Both must pass. Then check that the script still bites: put
   `"setup.default.agent.zzz": {"checked": "true"}` into a scratch copy of the
   built menu and run the script on it. It must exit non-zero naming the row.
   Traps: `python3 -I` is not needed, because the script is our own file; keep
   the shebang-less file plain. Do not let `nix fmt` touch the `.py` file. The
   repo formatter's file set decides; check that `nix fmt -- --ci` stays green.

2. **`tests/inline-python.nix` (new) and a `checks` entry in `flake.nix`,
   next to `grep-q-pipefail`.** Same shape as `tests/grep-q-pipefail.nix`
   (`lib.fileset.toSource` over `modules pkgs installer tests .github
   flake.nix`). An `awk` pass over `*.nix` and `*.sh` files: on a line
   matching `python3? +(-[A-Za-z]+ +)*-c +'$`, look at the next line; if it
   begins with whitespace, print `file:line` and fail. End with a count line
   and touch `$out`. A `# Why:` comment in `flake.nix` points at the test.
   → verify by `nix build .#checks.x86_64-linux.inline-python -L` passing.
   Then restore the old inline block in a scratch copy (do not commit it),
   rebuild, and confirm it fails naming `pkgs/omarchy/default.nix`.
   Traps: `tests/` is in the scanned set, so the test file must not contain
   the pattern itself in a form it would match. Build the pattern from parts,
   or keep it on a line that does not end in `'`. It is cheap and belongs in
   PR CI, so it is not added to `generated-checks.sh`'s `claimed` list.

3. **PR.** Fresh-agent review against this plan, `nix fmt -- --ci`, statix,
   deadnix, then open the PR. After merge, re-run #1199 step 5 (outside this
   plan).

### On `release` (branch `hotfix/1205`)

1. **`git worktree add ../nixarchy-hotfix-1205 -b hotfix/1205 origin/release`.**
   Apply the same change to release's script (`pkgs/omarchy/default.nix:1156-1186`
   on `release`). The code between `-c '` (`:1160`) and `' $menu` (`:1186`)
   goes to `pkgs/omarchy/check-menu.py`, and the call becomes
   `${python3}/bin/python3 ${./check-menu.py} $menu`. Release's script reads
   only `sys.argv[1]`. Do not bring step 2's check onto `release`: the hotfix
   carries the fix only.
   → verify by the same two omarchy builds as step 1, run in this worktree.
   Traps: a hotfix branch must contain nothing but the fix; check
   `git diff origin/release --stat` before committing.

2. **Whole stable system from the hotfix branch.** Build a stable toplevel
   wired like an installed stable machine (the same rewiring #1200 put into
   `stableVm`, written inline because `release` predates it):
   `nix build --no-link --impure --expr` over `builtins.getFlake` of the
   worktree, with `inputs // { nixpkgs = nixpkgs-stable; home-manager = home-manager-stable; self = <self with nixosModules.nixarchy and homeManagerModules.nixarchy re-imported from modules/*.nix> }`,
   `nixpkgs-stable.lib.nixosSystem { modules = [ stableInputs.self.nixosModules.nixarchy ./vm/configuration.nix ]; }`,
   then `.config.system.build.toplevel`. Announce on the agent bus first;
   this is an uncached stable build on p620.
   → it must build. If it fails on something other than #1205, **stop**:
   record it, open an issue, and tell the maintainer before any tag. The
   hotfix would not make stable buildable.
   Traps: `release` may lack `inputs.nixpkgs-stable` or
   `home-manager-stable`; check `flake.nix` on `release` first and pin them
   with `--override-input` if absent.

3. **Commit and push `hotfix/1205`. Stop and ask the maintainer to approve the
   tag.** Show them `git log --oneline origin/release..hotfix/1205` (one
   commit) and the step 4–5 results.

4. **On the go-ahead only:** `git tag -a v4.0.4-2 -m v4.0.4-2 hotfix/1205`,
   then `git push origin v4.0.4-2`. Watch `release.yml`: it must end green,
   with `release` at `v4.0.4-2`.
   Traps: never use `git commit -m` with backticks; use `-F`.

5. **Merge back.** Branch `chore/1205-merge-back-v4.0.4-2` from `origin/main`,
   `git merge -s ours v4.0.4-2 -m "..."` (with `-F`), push, and open a PR. It
   must be merged with **Create a merge commit**, not squash; say so in the PR
   body.
   → verify after merge:
   `git merge-base --is-ancestor origin/release origin/main` is true.

## Tests

- Step 1's two omarchy builds and the mutation check.
- Step 2's check: green on the tree, red on the restored inline block.
- `nix fmt -- --ci`, statix, deadnix: green.
- Hotfix: step 4's builds and step 5's whole stable toplevel.
- Release: `release.yml` green, `release` at `v4.0.4-2`, ancestor check true
  after the merge-back.

## Rollback

- `main`: revert the PR.
- Hotfix before the tag: delete `hotfix/1205`; nothing has shipped.
- After the tag: `release` never moves backwards. A bad `v4.0.4-2` is fixed
  forward with `v4.0.4-3` from `release`, by the same procedure.
