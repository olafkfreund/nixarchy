---
status: approved
issue: 1301
spec: spec/2026-10-17-1301-menu-guards-pacman-disabled.md
---

# Plan: The menu's package guards ask Nix, and installed apps dim on stable as they do on edge

Everything a coder needs is here. You do not need to open the intent or the
spec. Work only in `/mnt/data/vmtest/wt-1301`, on branch
`fix/1301-menu-guards-pacman-disabled`. Its base is origin/main `7e0ceac5`,
and the line numbers below were read at that commit.

## What is wrong

Omarchy's stock menu answers the package question with pacman. Its
`shell/plugins/menu/MenuModel.js` `guardHelpers()` defines bash *functions*
`omarchy-pkg-present` and `omarchy-pkg-missing` before it evaluates any
guard, and builds them from `pacman -Qq` / `pacman -Qi`. A function shadows
nixarchy's PATH command of the same name, so the menu never reaches it. On
NixOS pacman is a shim that refuses, so the menu always concludes "not
installed".

Stable Omarchy v4.0.4 also has no `disabled` support. `normalizeItem` drops
the field, so the 63 rows nixarchy marks `disabled` never dim, and the three
"Not available on NixOS" rows can be clicked.

## The approved decisions (from the spec, in substance)

1. **D1, the guards ask Nix, for every row.** `pkgs/omarchy/default.nix`
   rewrites the two lines of `guardHelpers()` that define `__omarchy_pkg_has`,
   using `substituteInPlace --replace-fail`. The new body applies nixarchy's
   own `omarchy-pkg-present` rule (`pkgs/omarchy/nix-bin/omarchy-pkg-present`)
   inside the shell: the name is a runnable command as written, or with
   `-bin` and then `-stable` removed. No new processes are started.

   The pacman snapshot lines above it stay as they are: they become dead
   code, and harmless. The two replaced lines read exactly the same on the
   stable pin (`MenuModel.js:417-418`) and on the edge pin (`:494-495`). The
   snapshot lines do not: edge builds them in `guardPackageSnapshot()`.
2. **D2, stable gets upstream's dimming.** Stable carries upstream's
   omacom/omarchy@4b93f8d84d (#6955, "Dim installed software in the Install
   menus instead of hiding it"), restricted to `shell/plugins/menu/Menu.qml`
   and `shell/plugins/menu/MenuModel.js`. It lives in
   `pkgs/omarchy/1301-menu-disabled.patch` and is applied with
   `patch --fuzz=0` after the existing patches. It is CARRIED until stable
   reaches a release that contains #6955.

   Edge already has this code, so an edge carry commit deletes the `patch`
   line (step 9). The precedent is `9958d4c1`, which dropped 1153 and 1155.

   The patch's content is frozen in step 1, because #1305 rebases its own
   `MenuModel.js` and `Menu.qml` edits onto it.
3. **D3, rows nixarchy dims are no longer also hidden.** In the generator's
   merge (`modules/apps.nix`), a row whose override has `disabled` does not
   inherit upstream's `when` **if that `when` calls `omarchy-pkg-*`**. Any
   other upstream `when` is still inherited. That matters for the 13
   `install.development.*` rows, which test for a mise or rustup directory.

   On stable this affects 39 rows. On edge it affects none, because upstream
   moved those rows from `when` to `disabled` itself.
4. **D4, Remove rows nixarchy has not ported stay hidden.** In the same
   python, an upstream `remove.*` row that is **not in nixarchy's overrides**
   and whose `when` calls `omarchy-pkg-*` gets `when = "false"`. That covers
   these six today:
   - `remove.service.tailscale`
   - `remove.security.fingerprint`
   - `remove.security.fido2`
   - `remove.ai.hermes`
   - `remove.ai.perplexity`
   - `remove.browser.brave-origin`

   Their actions are still upstream's Arch scripts, and #1304 owns those.
   Once #1304 overrides a row, this rule no longer touches it, so #1301 and
   #1304 can land in either order.
5. **D5, the three "Not available on NixOS" rows become unselectable through
   D2.** Their inherited Arch action is #1304's business, and stays as it is
   here.
6. **D6, a new check, `checks.menu-guards`.** It is a `runCommand` with no
   VM. node loads the tree's own `MenuModel.js`. The check builds the guard
   script with that model and runs it under bash twice, with nothing
   installed ("absent") and with every asked-about name stubbed on PATH
   ("present"). It then judges each row with `MenuModel.isVisible` and
   `MenuModel.isDisabled`. Rows are selected by rule, never from a list.

   Every group has a minimum count. A further assertion checks that the
   in-shell helper agrees with `bin/omarchy-pkg-present`. The check contains
   no #1303-specific cases. The hole it leaves is stated: `Menu.qml` (the
   QML that dims rows and blocks clicks) is not exercised.
7. **D7, documentation fixed in the same PR:**
   - `modules/AGENTS.md`;
   - `data/bin-ledger.nix`;
   - `pkgs/AGENTS.md` (a new section);
   - `tests/AGENTS.md` (the trap found while writing the check).
8. **D8, follow-ups for the owner to file, not done here.** nixarchy-menu
   (its own repository, with its own copy of `MenuModel.js`) has both bugs,
   and nixi may too.
9. **Coexistence (§14).** No NixOS or Home Manager option is set and
   nothing is merged into an environment. The user's menu extension is still
   merged over the defaults row by row and is never written. One visible
   change goes in the release notes: a user's own row that uses
   `omarchy-pkg-present` now gets the PATH-based answer instead of "always
   absent".

### Deviations from the spec, and why

- **The check runs `bash --noprofile --norc -c`, not `bash -lc`.** In the
  prototype on p620, a login shell sourced `/etc/profile`, which replaced
  PATH with the machine's own, so the "absent" world saw the user's real
  apps. The check exists to vary PATH, so it must not let the host overwrite
  it. The real menu's login-shell PATH is the machine's concern, and the
  hand check in step 8 covers it.
- **`displayRow` is not called.** The spec already dropped it in review.
  `isVisible` and `isDisabled` are the verdict.
- **The minimum for Remove rows nixarchy has not ported is 0, not 1.**
  #1304 will port all six, and a floor of 1 would then fail on a correct
  tree. The other groups' minimums still catch a parse that goes empty.

### Measured while planning (prototype, no nix build)

The check below was run with node 24 against scratch copies of the deployed
tree (`/nix/store/rla9km5s…-nixarchy-omarchy-tree`) and the upstream menu
(`/nix/store/1pmcfdgb…-omarchy-4.0.4/share/omarchy/default/omarchy/omarchy-menu.jsonc`).
With all four decisions applied it prints:

    {"disabled-no-when":50,"dims-on-path":48,"unavailable":3,"package-guarded":2,"upstream-guarded-remove":23,"unported-remove":6,"helper-agreement":600}
    menu guards answer what is installed, through the menu's own model

Each break in step 6 turned it red with the text quoted there.

## Steps

0. **Preconditions.**
   - `git -C /mnt/data/vmtest/wt-1301 status --short` prints nothing.
   - `git -C /mnt/data/vmtest/wt-1301 log --oneline -1` shows the commit
     that approves this plan.
   - `git -C /mnt/data/vmtest/wt-1301 merge-base origin/main HEAD` is
     `7e0ceac5…`. If origin/main has moved, rebase first (CLAUDE.md §9),
     then re-read every line number below.

   Traps: never `cd` into `/mnt/code/Source-home/nixarchy`. Other agents
   work in `/mnt/data/vmtest/wt-130x`; leave them alone.

1. **New file `pkgs/omarchy/1301-menu-disabled.patch`.** This is the
   frozen carried patch: upstream 4b93f8d84d's diff for exactly two files,
   byte for byte as GitHub serves it, with nothing added.

   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   cd /mnt/data/vmtest/wt-1301
   gh api -H 'Accept: application/vnd.github.v3.diff' \
     repos/omacom/omarchy/commits/4b93f8d84d > /mnt/data/vmtest/p1301-6955.diff
   python3 - /mnt/data/vmtest/p1301-6955.diff pkgs/omarchy/1301-menu-disabled.patch <<'PY'
   import re, sys
   parts = re.split(r'(?m)^(?=diff --git )', open(sys.argv[1]).read())
   keep = [p for p in parts if p.split('\n')[0] in (
       'diff --git a/shell/plugins/menu/Menu.qml b/shell/plugins/menu/Menu.qml',
       'diff --git a/shell/plugins/menu/MenuModel.js b/shell/plugins/menu/MenuModel.js')]
   assert len(keep) == 2, len(keep)
   open(sys.argv[2], 'w').write(''.join(keep))
   PY
   sha256sum pkgs/omarchy/1301-menu-disabled.patch
   git add pkgs/omarchy/1301-menu-disabled.patch
   ```

   Verify:
   - The sha256 is
     `b22d191772f9491820cd17eef40089bc3261875b5c7fe124a584a4c971ef2041`,
     and `wc -l` is 325. If either differs, stop and report; do not edit the
     file by hand.
   - The hunks must be exactly these 26 (`awk '/^diff --git/{f=$3}
     /^@@/{print f, $1, $2, $3}'`). This is the list #1305 rebases onto.
     - `Menu.qml`, 19 hunks:
       - `-317,6 +317,7`, `-382,6 +383,7`, `-470,9 +472,10`,
         `-495,8 +498,17`, `-504,7 +516,38`;
       - `-530,6 +573,7`, `-630,9 +674,7`, `-665,12 +707,12`,
         `-727,7 +769,7`, `-874,6 +916,7`;
       - `-947,6 +990,7`, `-966,6 +1010,7`, `-991,6 +1036,7`,
         `-1005,9 +1051,11`, `-1108,7 +1156,7`;
       - `-1211,6 +1259,7`, `-1218,6 +1267,9`, `-1330,7 +1382,7`,
         `-1339,6 +1391,7`.
     - `MenuModel.js`, 7 hunks:
       - `-34,7 +34,8` (normalizeItem keeps `disabled`);
       - `-83,7 +84,7` (mergeMenuSources root row);
       - `-270,10 +271,20` (`isDisabled`, `labelFor` ✓);
       - `-351,16 +362,17` (`displayRow` gains `disabledResults`);
       - `-459,10 +471,10` (guard comment);
       - `-472,6 +484,7` (`guardScript` emits `d:` lines);
       - `-497,6 +510,7` (exports `isDisabled`).
   - It is a dry run only, against the pinned source. The second command
     must print `exit=0`:

     ```bash
     src=$(nix flake archive --json . | jq -r '.inputs.omarchy.path')
     d=$(mktemp -d /mnt/data/vmtest/p1301.XXXX); cp -r "$src/shell" "$d/"; chmod -R u+w "$d"
     patch -d "$d" -p1 --dry-run --fuzz=0 < pkgs/omarchy/1301-menu-disabled.patch; echo "exit=$?"
     rm -rf "$d" /mnt/data/vmtest/p1301-6955.diff
     ```

     Expected output: `Hunk #16..#19 succeeded … (offset 1|6 lines)`, then
     `exit=0`.

   Traps:
   - The file must be `git add`ed, or the flake cannot see it.
   - Use a scratch directory under `/mnt/data/vmtest`, not `/tmp`, for
     anything large (§5).
   - Do not add a header to the patch: the hash is the freeze.

2. **`pkgs/omarchy/default.nix:2090`, plus two new files: apply the patch
   and the guard substitution (D1, D2).**
   - New file `pkgs/omarchy/1301-pkg-has.old.js`, exactly two lines, each
     starting with four spaces:

     ```
         + '__omarchy_pkg_has() { [[ -n ${__omarchy_pkgs[$1]-} ]] && return 0; '
         + '[[ $1 == *[\\<\\>=]* ]] && { pacman -Q "$1" &>/dev/null; return; }; return 1; }\n'
     ```

   - New file `pkgs/omarchy/1301-pkg-has.new.js`, exactly two lines:

     ```
         + '__omarchy_pkg_has() { local c=${1%-bin}; c=${c%-stable}; '
         + 'command -v "$1" &>/dev/null || command -v "$c" &>/dev/null; }\n'
     ```

     The `\\<\\>` and `\n` are literal characters in the file. They are
     JavaScript string escapes inside `MenuModel.js`, not shell escapes.
     Write both files with the Write tool, not with `echo`.
   - In `pkgs/omarchy/default.nix`, insert after line 2090
     (`patch … < ${./902-notification-sender-close.patch}`) and before the
     blank line and `# Wear the snowflake.`:

     ```nix

                         # Omarchy's menu answers omarchy-pkg-present from pacman (#1301); this
                         # carries upstream's dimming (omacom/omarchy#6955) until stable has it,
                         # and asks the PATH the way nix-bin/omarchy-pkg-present does.
                         # Why: pkgs/AGENTS.md#the-menu-asks-pacman-and-ignores-disabled-1301
                         patch -d "$out/share/omarchy" -p1 --forward --fuzz=0 < ${./1301-menu-disabled.patch}
                         substituteInPlace $out/share/omarchy/shell/plugins/menu/MenuModel.js \
                           --replace-fail "$(cat ${./1301-pkg-has.old.js})" "$(cat ${./1301-pkg-has.new.js})"
     ```

     Match the indentation of line 2090 exactly: it is 20 spaces inside the
     indented string. The `substituteInPlace $out/share/omarchy/…` path form
     is deliberate: `tests/patched-files.nix` greps that form to list the
     files the port touches.
   - `git add pkgs/omarchy/1301-pkg-has.old.js pkgs/omarchy/1301-pkg-has.new.js`

   Verify:
   - `nix fmt`, then `git diff --stat`: only `pkgs/omarchy/default.nix`
     changes, by about 8 lines. If the diff is hundreds of lines, the
     nixpkgs-fmt hook rewrote the file. Run `nix fmt` again and re-check
     (§5).
   - Arg length: `drv=$(nix eval --raw .#checks.x86_64-linux.install-phase-budget.drvPath) && flock /mnt/data/vmtest/codex-build.lock nix build --no-link -L "$drv^*"`. Its budget is 123000 bytes, the phase is 119372 bytes
     at `7e0ceac5`, and this step adds about 600. If the budget fails, shorten
     the comment; do not raise the budget.
   - Build the package. This is the non-cheap tier, so first check that
     `pgrep -fc '^(nix build|nh os build|nixos-rebuild).*p620'` prints 0 and
     the 1-minute load is below 12. Then:

     ```bash
     drv=$(nix eval --raw .#packages.x86_64-linux.omarchy.drvPath)
     out=$(nix build --no-link --print-out-paths "$drv^*")
     m=$out/share/omarchy/shell/plugins/menu/MenuModel.js
     grep -c 'local c=${1%-bin}' "$m" || true   # 1
     grep -c 'pacman -Q "$1"' "$m" || true      # 0 (grep -c exits 1 on zero matches)
     grep -c 'function isDisabled' "$m" || true # 1
     grep -c 'disabledResults' "$out/share/omarchy/shell/plugins/menu/Menu.qml" || true  # > 0
     ```

   Traps:
   - New files must be `git add`ed.
   - `nix fmt` after the `.nix` edit, then read `git diff --stat`.
   - No heredoc inside the `''` string: the two `.js` files exist to avoid
     one.
   - `MAX_ARG_STRLEN`: keep the comment to four lines. See pkgs/AGENTS.md,
     "Why the install phase says so little", and `checks.install-phase-budget`.
   - If `--replace-fail` reports no match, the old file's whitespace is
     wrong. Compare with `sed -n 417,418p` of the pinned `MenuModel.js`; do
     not loosen the match.

3. **`modules/apps.nix:972-1031`, the generator python (D3, D4).** Three
   edits, all inside the existing `python3 - … <<'PY'` block:
   - After line 983 (`arch_map = json.load(open(archmap_path))`), add:

     ```python
             # Upstream's `omarchy-pkg-*` guards, which the menu answers from the PATH (#1301).
             PKG_GUARD = re.compile(r"\bomarchy-pkg-(present|missing)\b")
     ```

   - After the arch-map rewrite loop ends (line 1007, the closing `}` of the
     `overrides[row_id] = {…}` dict) and before `out = {}` (line 1009), add:

     ```python

             # An upstream remove row nixarchy has not ported still runs Arch's script,
             # so it stays hidden however the guard answers. #1304 ports them row by row;
             # a row it overrides is in `overrides` and this leaves it alone.
             for row_id, row in upstream.items():
                 if (row_id.startswith("remove.") and row_id not in overrides
                         and PKG_GUARD.search(str(row.get("when", "")))):
                     overrides[row_id] = {"when": "false"}
     ```

   - In the merge loop, change lines 1028-1030 from

     ```python
                     for key, value in base.items():
                         if key not in merged and value not in ("", [], None):
                             merged[key] = value
     ```

     to

     ```python
                     for key, value in base.items():
                         if key not in merged and value not in ("", [], None):
                             # A row we dim must not also be hidden by upstream's package guard.
                             if key == "when" and "disabled" in merged and PKG_GUARD.search(str(value)):
                                 continue
                             merged[key] = value
     ```

   Verify (cheap tier, under `flock /mnt/data/vmtest/codex-build.lock`):

   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   cd /mnt/data/vmtest/wt-1301
   drv=$(nix eval --raw '.#nixosConfigurations.reference.config.environment.etc."nixarchy/omarchy-menu.jsonc".source.drvPath')
   menu=$(flock /mnt/data/vmtest/codex-build.lock nix build --no-link --print-out-paths "$drv^*")
   python3 - "$menu" <<'PY'
   import json, re, sys
   raw = re.sub(r"^\s*//[^\n]*(\n|$)", "", open(sys.argv[1]).read(), flags=re.M)
   rows = json.loads(re.sub(r",(\s*[}\]])", r"\1", raw))
   P = re.compile(r"\bomarchy-pkg-(present|missing)\b")
   both = [k for k, v in rows.items() if "disabled" in v and P.search(str(v.get("when", "")))]
   hidden = sorted(k for k, v in rows.items() if k.startswith("remove.") and v.get("when") == "false")
   dev = [k for k, v in rows.items() if k.startswith("install.development.") and "disabled" in v and v.get("when")]
   print("both", len(both), "hidden", hidden, "dev-when", len(dev))
   assert not both and len(dev) == 13 and len(hidden) == 6, "unexpected"
   PY
   ```

   Expected output:

       both 0 hidden ['remove.ai.hermes', 'remove.ai.perplexity', 'remove.browser.brave-origin', 'remove.security.fido2', 'remove.security.fingerprint', 'remove.service.tailscale'] dev-when 13

   Then run `nix fmt` and `git diff --stat`.

   Traps:
   - This python sits inside a Nix `''` string. Do not write `''` or `${`
     in it. The `\b` is fine as it is.
   - `nix fmt`, then read `git diff --stat`.

4. **New files `tests/menu-guards.js` and `tests/menu-guards.nix`, and
   `flake.nix:1981-1985`: the check (D6).**
   - `tests/menu-guards.js`, verbatim. This is the prototype measured
     above:

     ```js
     // checks.menu-guards: judge the menu's guards with the menu's own code (#1301).
     // usage: node menu-guards.js <tree> <upstream-menu.jsonc> <basePATH> <workdir> <bash>
     "use strict"
     const fs = require("fs")
     const path = require("path")
     const { spawnSync } = require("child_process")

     // bash by absolute path: a bare "bash" resolves through node's own PATH. stdin
     // is never a socket: bash sources /etc/bashrc when it is, which resets PATH.
     const [tree, upstreamMenu, basePath, work, bash] = process.argv.slice(2)
     const M = require(path.join(tree, "shell/plugins/menu/MenuModel.js"))
     const PKG = /\bomarchy-pkg-(present|missing)\b/
     const failures = []
     const fail = (msg) => failures.push(msg)

     const load = (file) => M.mergeMenuSources(M.parseMenuJsonc(fs.readFileSync(file, "utf8")), [])
     const menu = load(path.join(tree, "default/omarchy/omarchy-menu.jsonc"))
     const rows = menu.items
     const ids = Object.keys(rows)
     // normalizeItem keeps only the keys MenuModel.js knows, so `disabled` is read
     // from the raw file: an unpatched model would drop it and the check must say so.
     const raw = JSON.parse(M.stripJsonc(fs.readFileSync(path.join(tree, "default/omarchy/omarchy-menu.jsonc"), "utf8")))

     // Every name a guard asks about, from both menus.
     const names = new Set()
     for (const src of [raw, JSON.parse(M.stripJsonc(fs.readFileSync(upstreamMenu, "utf8")))]) {
       for (const row of Object.values(src)) {
         for (const f of ["when", "checked", "disabled"]) {
           const s = String((row && row[f]) || "")
           for (const m of s.matchAll(/omarchy-pkg-(?:present|missing)((?:\s+[A-Za-z0-9._@+-]+)+)/g))
             for (const n of m[1].trim().split(/\s+/)) {
               names.add(n)
               names.add(n.replace(/-bin$/, "").replace(/-stable$/, ""))
             }
           for (const m of s.matchAll(/command -v\s+([A-Za-z0-9._@+-]+)/g)) names.add(m[1])
         }
       }
     }

     function world(name, present) {
       const dir = path.join(work, name)
       const bin = path.join(dir, "bin")
       const home = path.join(dir, "home")
       fs.mkdirSync(bin, { recursive: true })
       fs.mkdirSync(path.join(home, ".config/nixarchy"), { recursive: true })
       fs.writeFileSync(path.join(home, ".config/nixarchy/apps.nix"), "{ }\n")
       if (present) for (const n of names) fs.writeFileSync(path.join(bin, n), "#!/bin/sh\nexit 0\n", { mode: 0o755 })
       const env = { PATH: bin + ":" + basePath, HOME: home }
       const script = M.guardScript(rows)
       const r = spawnSync(bash, ["--noprofile", "--norc", "-c", script], { env, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] })
       if (r.status !== 0) fail(`${name}: guard batch exited ${r.status}: ${r.stderr}`)
       const res = { w: {}, c: {}, d: {} }
       for (const line of r.stdout.split("\n")) {
         const m = line.trim().match(/^(.*):([wcd]):([01])$/)
         if (m) res[m[2]][m[1]] = m[3] === "1"
       }
       const visible = (id) => M.isVisible(rows, menu.itemOrder, res.w, rows[id])
       const dim = (id) => {
         if (typeof M.isDisabled !== "function")
           throw new Error(`MenuModel.isDisabled is not a function: this menu cannot dim ${id}`)
         return M.isDisabled(res.d, rows[id])
       }
       return { env, visible, dim }
     }

     const absent = world("absent", false)
     const present = world("present", true)

     const install = ids.filter((id) => id.startsWith("install.") && raw[id])
     const withDisabled = install.filter((id) => raw[id].disabled)
     const counts = {}
     const count = (k) => (counts[k] = (counts[k] || 0) + 1)

     for (const id of withDisabled) {
       const d = String(raw[id].disabled)
       if (raw[id].when && PKG.test(raw[id].when))
         fail(`${id}: has disabled and a package-guard when (${raw[id].when}), so an installed app is hidden instead of dimmed`)
       if (!raw[id].when) {
         count("disabled-no-when")
         if (!absent.visible(id)) fail(`${id}: hidden in absent`)
         if (!present.visible(id)) fail(`${id}: hidden in present, where it should be dim`)
       }
       if (d === "true") {
         count("unavailable")
         if (!absent.dim(id) || !present.dim(id)) fail(`${id}: "Not available" row is selectable`)
       } else if (/command -v|omarchy-pkg-/.test(d)) {
         count("dims-on-path")
         if (absent.dim(id)) fail(`${id}: dim with nothing installed`)
         if (!present.dim(id)) fail(`${id}: not dim with its command installed`)
       }
     }

     for (const id of install) {
       const r = raw[id]
       const inWhen = PKG.test(String(r.when || ""))
       const inDisabled = PKG.test(String(r.disabled || ""))
       if (!inWhen && !inDisabled) continue
       count("package-guarded")
       if (!absent.visible(id) || (inDisabled && absent.dim(id))) fail(`${id}: not offered with nothing installed`)
       if (inWhen && present.visible(id)) fail(`${id}: visible with its package present (${r.when})`)
       if (inDisabled && !present.dim(id)) fail(`${id}: not dim with its package present (${r.disabled})`)
     }

     const upRaw = JSON.parse(M.stripJsonc(fs.readFileSync(upstreamMenu, "utf8")))
     for (const id of Object.keys(upRaw)) {
       if (!id.startsWith("remove.") || !PKG.test(String(upRaw[id].when || ""))) continue
       count("upstream-guarded-remove")
       if (!raw[id]) { fail(`${id}: upstream's remove row is missing from the generated menu`); continue }
       // A row nixarchy ported has its own action; #1304 owns those.
       if (raw[id].action !== upRaw[id].action) continue
       count("unported-remove")
       if (present.visible(id)) fail(`${id}: visible with its package present, and still runs upstream's ${upRaw[id].action}`)
     }

     // The in-shell helper and the shipped command must give the same answer.
     const helper = path.join(tree, "bin/omarchy-pkg-present")
     const sample = [...names]
     for (const [wn, w] of [["absent", absent], ["present", present]]) {
       const prelude = M.guardScript({ probe: { id: "probe", when: "true" } }).split("if {")[0]
       for (const n of sample.concat(sample.map((s) => s + "-bin"), sample.map((s) => s + "-stable"))) {
         const inShell = spawnSync(bash, ["--noprofile", "--norc", "-c", prelude + 'omarchy-pkg-present "$1"', "x", n], { env: w.env, stdio: "ignore" }).status
         const shipped = spawnSync(helper, [n], { env: w.env, stdio: "ignore" }).status
         count("helper-agreement")
         if ((inShell === 0) !== (shipped === 0)) fail(`${wn}: omarchy-pkg-present ${n}: the menu says ${inShell === 0}, bin/omarchy-pkg-present says ${shipped === 0}`)
       }
     }

     const floors = { "disabled-no-when": 30, unavailable: 3, "dims-on-path": 40, "package-guarded": 1, "upstream-guarded-remove": 1, "unported-remove": 0, "helper-agreement": 60 }
     for (const [k, min] of Object.entries(floors))
       if ((counts[k] || 0) < min) fail(`only ${counts[k] || 0} ${k} cases, expected at least ${min}: the menu changed shape or this check stopped reading it`)

     console.log(JSON.stringify(counts))
     if (failures.length) {
       console.error(failures.length + " failure(s):\n" + failures.join("\n"))
       process.exit(1)
     }
     console.log("menu guards answer what is installed, through the menu's own model")
     ```

   - `tests/menu-guards.nix`:

     ```nix
     { inputs, pkgs }:
     # The menu's guards, judged by the menu's own model (#1301). The guard batch
     # once defined omarchy-pkg-present from pacman, and nixarchy's `disabled`
     # was dropped by stable's normalizeItem; the old check ran each condition
     # with bash -c and so could see neither. Two worlds differ only in what is
     # on PATH. Menu.qml is not exercised: dimming and blocked clicks are QML.
     # Why: tests/AGENTS.md#menu-guards-runs-the-menu-s-model-not-the-strings
     let
       cfg = inputs.self.nixosConfigurations.reference.config.programs.nixarchy;
       basePath = pkgs.lib.makeBinPath [
         pkgs.coreutils
         pkgs.gnugrep
         pkgs.gawk
         pkgs.bash
       ];
     in
     pkgs.runCommand "nixarchy-menu-guards" { } ''
       ${pkgs.nodejs}/bin/node ${./menu-guards.js} \
         ${cfg.tree} \
         ${cfg.package}/share/omarchy/default/omarchy/omarchy-menu.jsonc \
         ${basePath} "$TMPDIR/worlds" ${pkgs.bash}/bin/bash
       touch $out
     ''
     ```

   - In `flake.nix`'s `uniformChecks` list, insert `"menu-guards"` between
     `"machine-name-free"` (line 1981) and the comment above `"menu-verbs"`
     (lines 1982-1985). Give it a one-line comment:
     `# The menu's guards through its own model, absent and present (#1301).`
   - `git add tests/menu-guards.js tests/menu-guards.nix`

   Verify, cheap tier:

   ```bash
   cd /mnt/data/vmtest/wt-1301
   drv=$(nix eval --raw .#checks.x86_64-linux.menu-guards.drvPath)
   flock /mnt/data/vmtest/codex-build.lock nix build --no-link -L "$drv^*"
   ```

   The log ends with the counts line and
   `menu guards answer what is installed, through the menu's own model`.
   Record the counts line. On stable, expect `"unported-remove":6`,
   `"package-guarded":2` and `"upstream-guarded-remove":23`.

   Traps:
   - New files must be `git add`ed.
   - Evaluate the drvPath first, then build `'<drv>^*'`. Do not build by
     attribute path while you edit the tree (§5).
   - `nix fmt`, then `git diff --stat`.
   - This is a `uniformChecks` entry, so CI runs it with no workflow edit
     (§4). Do not touch `.github/`.

5. **Commit a known-good baseline, with the real subject from the start.**

   ```bash
   git status --short   # only the eight paths below
   git add -A
   git commit -m "The menu's package guards ask the PATH instead of pacman, and installed apps dim on stable as they do on edge (#1301)" \
     -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
   ```

   It is never a `wip:` subject (§8). Step 7 amends the docs into this same
   commit, so the branch is one commit whenever the coder stops. Then check
   `git show --stat HEAD`. It must list exactly:
   - `pkgs/omarchy/1301-menu-disabled.patch`
   - `pkgs/omarchy/1301-pkg-has.old.js`
   - `pkgs/omarchy/1301-pkg-has.new.js`
   - `pkgs/omarchy/default.nix`
   - `modules/apps.nix`
   - `tests/menu-guards.js`
   - `tests/menu-guards.nix`
   - `flake.nix`

6. **The §1 proof for `checks.menu-guards`: four breaks, each red, then
   restored and green.**

   For each break:
   1. Apply it.
   2. Show that it landed: `git diff` must show exactly the removed lines.
   3. `git add -A`, because the flake sees only tracked files.
   4. Re-evaluate the drvPath, then build `"$drv^*"` with `-L`, without
      piping its status: run `set -o pipefail` first if you `tee` the log.
   5. Save the red output to `/mnt/data/vmtest/p1301-break-N.log`.
   6. Restore with `git checkout HEAD -- <path>`. Never use
      `git checkout -- <path>`, which restores the index and therefore the
      break (§5).
   7. Check `git status --short` is empty.

   | # | break (delete these lines) | expected red (from the prototype) |
   |---|---|---|
   | 1 | the `substituteInPlace … 1301-pkg-has…` two lines in `default.nix` (D1) | `302 failure(s):`, including `install.ai.hermes: visible with its package present (! omarchy-pkg-present hermes-desktop)` and `present: omarchy-pkg-present sdl-freerdp: the menu says false, bin/omarchy-pkg-present says true` |
   | 2 | the `patch … 1301-menu-disabled.patch` line (D2) | `Error: MenuModel.isDisabled is not a function: this menu cannot dim install.browser.chrome` |
   | 3 | the three-line `if key == "when" and "disabled" in merged …` skip in `apps.nix` (D3) | `40 failure(s):`, starting `install.browser.chrome: has disabled and a package-guard when (! omarchy-pkg-present google-chrome), so an installed app is hidden instead of dimmed` |
   | 4 | the remove-row `for` loop in `apps.nix` (D4) | `6 failure(s):`, including `remove.service.tailscale: visible with its package present, and still runs upstream's omarchy-launch-floating-terminal-with-presentation omarchy-remove-service-tailscale` |

   Exact counts can differ by a row or two if the reference machine's menu
   differs from p620's. The named lines must appear. Breaks 1 and 2 rebuild
   the `omarchy` package, so the non-cheap tier gate in step 2 applies.
   After the four restores, rebuild the check once more and see it green.

   Traps:
   - Verify each break landed before reading any green, because a silent
     no-op break looks the same as a blind check (§1).
   - Use `git checkout HEAD --`.
   - Do not pipe a status you need.
   - If a break unexpectedly stays green, grep the tree for a second place
     that provides the same property (§1) before calling the check blind.

7. **Documentation (D7).** All four are `.md` or ledger edits.
   - `modules/AGENTS.md:1792-1794`. The sentence ends "which is what
     upstream already uses for "you have this installed"." Replace that
     ending with: "which upstream uses for "you have this installed" since
     omacom/omarchy#6955. Stable v4.0.4 predates it and carries it as
     `pkgs/omarchy/1301-menu-disabled.patch` (#1301)."
   - `data/bin-ledger.nix:392-395`, the `omarchy-pkg-present` reason. After
     "…check the app selection themselves.", append: " The stock menu does
     not call this command: its guard batch defines a function of the same
     name, which #1301 makes answer by the same rule, inside the shell."
     Do the same for `omarchy-pkg-missing` at 388-391.
   - `data/bin-ledger.nix:379-383` and `396-400` (`omarchy-pkg-drop` and
     `omarchy-pkg-remove`). The `pacman` text says no menu row reaches them.
     Append: " The remove rows nixarchy has not ported are kept hidden by the
     generator (`when = "false"`, #1301) until #1304 ports them."
   - `pkgs/AGENTS.md`: append a new section at the **end** of the file, so
     no anchor moves. Title: `## The menu asks pacman, and ignores disabled
     (#1301)`, with an `<a id="the-menu-asks-pacman-and-ignores-disabled-1301"></a>`
     line above it. 15 to 25 lines covering:
     - the shadowing function, and why the PATH command never answered;
     - why the fix is in-shell: the batch avoids forks, and node's agreement
       test keeps the in-shell copy and the script together;
     - that the patch is CARRIED from omacom/omarchy@4b93f8d84d, and only
       its two menu files;
     - the drop condition: stable reaching #6955. Edge already dropped it
       (step 9);
     - that #1305 rebases onto this patch;
     - that the pacman snapshot is left dead on purpose, and why (edge's
       `guardPackageSnapshot()` text differs).
   - `tests/AGENTS.md`: append at the end, with the anchor
     `<a id="menu-guards-runs-the-menu-s-model-not-the-strings"></a>` and
     the title `## menu-guards runs the menu's model, not the strings
     (#1301)`. Cover:
     - why running a condition with `bash -c` cannot see a function the
       menu's batch defines;
     - the two-world design;
     - the stated `Menu.qml` hole;
     - the trap found while writing it, as one general paragraph: **bash
       spawned by node with a socket on stdin sources `/etc/bashrc`, and
       on NixOS that resets PATH.** `bash -l` sources `/etc/profile`, which
       does the same. So a check that varies PATH must spawn bash with
       stdin ignored, `--noprofile --norc`, and an absolute path. Measured
       on p620 while planning: the "absent" world found
       `/run/current-system/sw/bin/sdl-freerdp`.

   Verify:
   - `drv=$(nix eval --raw .#checks.x86_64-linux.bin-ledger.drvPath) && flock /mnt/data/vmtest/codex-build.lock nix build --no-link "$drv^*"`
     is green.
   - `grep -n 'the-menu-asks-pacman-and-ignores-disabled-1301' pkgs/AGENTS.md pkgs/omarchy/default.nix`
     finds both the anchor and the pointer.
   - `grep -n 'menu-guards-runs-the-menu' tests/AGENTS.md tests/menu-guards.nix`
     finds both.

   Then fold the docs into the single commit:
   `git add -A && git commit --amend --no-edit`. Check that
   `git show --stat HEAD` lists the eight paths from step 5 plus
   `modules/AGENTS.md`, `data/bin-ledger.nix`, `pkgs/AGENTS.md` and
   `tests/AGENTS.md`.

   Traps: the ledger is a `.nix` file, so run `nix fmt` and read
   `git diff --stat`.

8. **Other cheap checks, then hand off to CI and to the owner.**
   - One at a time under the lock, each by drvPath:
     - `checks.patched-files`;
     - `checks.menu-verbs`;
     - `checks.remote-tunnel` (it greps the generated menu);
     - `checks.bin-ledger`.
   - `nix fmt -- --ci`.
   - `nix run nixpkgs#statix -- check .`
   - `nix run nixpkgs#deadnix -- --fail .`
   - `checks.options` and `checks.session` go to CI. Run them locally only
     if `gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`
     prints 0.
   - **Owner, after merge and a deploy:**
     - Install > Editor shows Helix dimmed with ✓ when `hx` is on PATH;
     - Sublime Text is dim and does nothing when clicked;
     - Remove > Service has no Tailscale row;
     - an app that is not installed is still offered.

     This covers the `Menu.qml` hole and the real login-shell PATH. Switching
     p620 restarts the CI runners and kills installs in flight, so check the
     queue first (§6).

   Traps:
   - Do not build a VM check while CI has an install in flight (§6).
   - Never `pkill` by name.

9. **ON THE EDGE BRANCH, AFTER MAIN MERGES: an edge carry commit.**

   This is a separate commit on a separate PR or integration, not part of
   the main PR. Edge's pin (quattro `cce8b1c`) already has #6955, so the
   patch line fails there: `--forward` reports "Reversed (or previously
   applied) patch detected" and patch exits 1.
   - In the edge integration branch, after main's merge is merged in, delete
     the `patch … ${./1301-menu-disabled.patch}` line and the comment's
     carry clause in `pkgs/omarchy/default.nix`. Keep the
     `substituteInPlace` line, whose text matches edge's `MenuModel.js:494-495`.
   - Delete `pkgs/omarchy/1301-menu-disabled.patch` on edge.
   - Add one line to the `pkgs/AGENTS.md` section saying edge dropped it.
   - Subject, in the existing register: "Edge: drop the 1301 menu patch,
     which quattro already carries (#1301)".
   - Verify:
     - edge's `omarchy` package builds (non-cheap tier gate);
     - `checks.menu-guards` is green against edge's tree. Rows nixarchy
       overrides keep nixarchy's own `command -v` `disabled`. Only the
       Install rows nixarchy does not override carry upstream's
       `disabled: omarchy-pkg-present …`, and those make up
       `"package-guarded"` (at least hermes and perplexity). Record the
       counts.
     - If a minimum fails on edge, report the counts. Do not lower a
       minimum without saying so in the commit.

   Traps: the edge workflow (#1278): work in its own worktree, and run no
   `git checkout` in a tree another process drives (§5).

10. **PR (only when the owner says so; pushing is also the owner's call).**
    - The branch is already one commit with the real subject (steps 5 and
      7). Check `git log --oneline origin/main..HEAD` shows exactly that one
      commit, plus the artifact commits (intent, spec, plan and their
      approvals). Never a `wip:` subject (§8).
    - Title: "The menu's package guards ask the PATH instead of pacman, and
      installed apps dim on stable as they do on edge".
    - Body, following `.github/PULL_REQUEST_TEMPLATE.md`:
      - **What this changes, and why:**
        - D1–D6 in one paragraph each;
        - links to intent/, spec/ and plan/;
        - which steps the coder did and which the lead finished;
        - the release-note line from D9;
        - the D8 follow-ups for the owner to file in nixarchy-menu.
      - **How I proved the check fails:** the four red outputs from step 6,
        each with its break, and the green rerun.
      - **Checks run locally:** the step 7/8 list, and that options and
        session were left to CI.
      - **What this cost:** the node/bash `/etc/bashrc` trap, and that it
        went into tests/AGENTS.md.
    - Write `closes #1301` once. Use `Refs #1304`, `Refs #1305` and
      `Refs #1303` for the related issues, never "closes … in part".
    - Never write the literal skip-CI marker anywhere in the body; say "a
      skip-CI marker" if it ever has to be named (§8).
    - After merge, check `gh issue view 1301 --json state` and the merge
      state (`gh pr view --json mergeable`) rather than assuming.

## Tests

| command | expected |
|---|---|
| `nix build "$(nix eval --raw .#checks.x86_64-linux.menu-guards.drvPath)^*" -L` | counts line, then `menu guards answer what is installed, through the menu's own model` |
| the step 6 breaks 1-4 | each red with the quoted line, then green after `git checkout HEAD --` |
| step 3's python against the generated menu | `both 0 hidden [6 rows] dev-when 13` |
| step 2's greps against the built `omarchy` | `1`, `0`, `1`, `>0` |
| `checks.patched-files`, `menu-verbs`, `remote-tunnel`, `bin-ledger` | green |
| `nix fmt -- --ci`, statix, deadnix | clean |
| CI: `options`, `session`, `omarchy`, generated-checks step | green; confirm `menu-guards` appears in the generated step's list in the run log |
| owner on hardware | the four observations in step 8 |

## Rollback

- Revert the squash commit on main: `git revert <sha>`. That removes the
  patch, the substitution, the generator change and the check together.
  The menu then goes back to today's behaviour: guards always say absent,
  and nothing dims on stable.
- Partial rollback is not supported. D3 without D1 is harmless, but D1
  without D3 hides 39 installed apps on stable, and D1 without D4 exposes
  six Arch remove scripts. `checks.menu-guards` fails in both cases, which
  is the point.
- On edge, revert step 9's carry in the same integration that brings in
  main's revert. Otherwise the carry's deletion of the patch line conflicts
  with a file that no longer has it.
