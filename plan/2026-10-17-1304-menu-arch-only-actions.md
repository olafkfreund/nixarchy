---
status: draft
issue: 1304
spec: spec/2026-10-17-1304-menu-arch-only-actions.md
---

# Plan: Menu rows that still run Omarchy's Arch-only or imperative scripts

## Summary of the approved decisions

You should not need to open the intent or the spec. Everything they decided
is here.

### Where to look

- **Deployed tree, for evidence:**
  `/nix/store/rla9km5silzbp6h9dcfz0pd1p90ia8r9-nixarchy-omarchy-tree`,
  written `$T` below. Use absolute paths, because the shell's `PATH` may still
  reach a stale tree.
- **Merged menu:** `/etc/nixarchy/omarchy-menu.jsonc`.
- **Upstream source:** `inputs.omarchy`, which is
  `/nix/store/3pyxkhsadqhyrcm57inxgb9dax4r5vb2-source` at this lock.
- **Line numbers:** every repo line number below is at `origin/main` 7e0ceac5.
  If a later Part starts from a newer `main`, re-find each anchor by its text.
  The text is what matters, not the number.

### Mechanisms

Every change uses one of three:

- **Menu override.** An entry in the `overrideSpec` literal in
  `modules/apps.nix:344-846`, or a rule in the python generator inside
  `menuDefaults` (`modules/apps.nix:963-1060`).
  - The generator copies every key an override leaves out from upstream's
    row, so `"<id>".when = "false";` hides a row and keeps its label, icon
    and action.
  - The literal is merged first, then generated app, service and flatpak
    rows are merged on top with `//`. Before you add an id, check it does
    not appear in a generated set:
    `grep -n '"<id>"' /etc/nixarchy/omarchy-menu.jsonc` shows the row, and
    a `description` of "Enable in …" or "Remove from …" means it is
    generated.
- **Patch.** `substituteInPlace $out/share/omarchy/bin/<name> --replace-fail
  '<anchor>' '<text>'` in `pkgs/omarchy/default.nix`. The patches go after the
  PAM drift guard (`:1469-1472`), and the PAM patches themselves sit at
  `:1386-1468`.
- **Replace.** A file in `pkgs/omarchy/nix-bin/`, with the upstream name and
  its `# omarchy:summary=` line kept. `default.nix:1101-1115` installs it over
  upstream's copy, and the build patches its shebang.

Every patch or replacement needs its `data/bin-ledger.nix` row in the same
commit (`pkgs/AGENTS.md`, "A patch needs its ledger row in the SAME change").
`checks.bin-ledger` refuses otherwise.

### The 15 decisions

1. **Delivery.** There are four PRs, one per class, in the order class 1, 2,
   4, 3 (Parts 1 to 4 below). Part 1 is on `fix/1304-menu-arch-only-actions`.
   Each later Part branches from `main` after the previous PR has merged.
   #1301 may land before or after any of them (decision 13).
2. **`remove.preinstalls` and `install.preinstalls`.** Both scripts are
   replaced so that they guard ownership. Reporting the problem upstream is
   pending the owner; nothing is filed.
   - **Remove deletes a launcher** in `~/.local/share/applications` only when
     all four hold:
     - its basename is one that `$OMARCHY_PATH/applications` ships;
     - the shipped copy's `Exec=` is a web app, a handler or a TUI
       (`omarchy-launch-webapp`, `omarchy-webapp-handler`, or
       `xdg-terminal-exec --app-id=TUI.`), which is 13 of the 16 files. foot,
       imv and mpv are never touched;
     - it is a regular file, not a link;
     - it is `cmp -s`-identical to the shipped copy.
   - **Remove deletes a `~/.local/bin` entry** only from upstream's list plus
     `cursor-agent` and `muse`, and only when it is a regular file whose whole
     content is the four-line stub `omarchy-mise-install` writes. It never
     deletes icons. It drops `omarchy-pkg-drop` and prints the app-selection
     route instead. The Hermes branch is unchanged.
   - **Restore** copies only launchers that are missing (no file and no link
     of that name). It writes no mise stubs, prints the app-selection route,
     and always clears the marker.
   - First-login provisioning has the same `cp -f` and mise-stub hazard. That
     is a follow-up for the owner to file; this series does not touch it.
3. **The sibling generator rule.** A `remove.X` row that is not overridden,
   whose `install.X` sibling is overridden to `nixarchy-app-enable <a>` or
   `nixarchy-service-enable <s>`, becomes the matching disable command.
   - **Its `when`:** the apps.nix selection grep for apps, or the services.nix
     `#@ <s>` marker grep for services.
   - **What it catches today:** 13 development rows (go, python, zig, rust,
     java, dotnet, ocaml, clojure, scala, node to `nodejs`, bun, deno, elixir)
     plus `remove.service.tailscale`. In Part 4 it also catches
     `remove.gaming.geforce-now`.
   - **Phoenix:** `remove.development.elixir.phoenix` is hidden, because its
     arm removes Elixir and Erlang. rails and laravel are unchanged.
4. **DNS.** `omarchy-dns` is patched to print the declarative route and exit
   1 at `require_root "$provider"`. The no-argument query is unchanged. The
   DHCP, Cloudflare and Google rows get the floating-terminal wrapper.
5. **sshd.** `setup.security.sshd` becomes `nixarchy-service-enable openssh`,
   with the services.nix marker test as `disabled`. `remove.security.sshd`
   becomes `nixarchy-service-disable openssh`, with the marker as `when`.
6. **Sudoless Docker.** Both scripts are patched to print the route and exit
   1: rootless Docker needs no group, and the rooted daemon's group is set in
   `users.users.<name>.extraGroups`.
7. **Fingerprint and FIDO2 removal.** Both become guidance and exit 1.
   - Neither drops packages any more. The fingerprint script no longer runs
     `rm /etc/pam.d/omarchy-lock-fingerprint`, and the FIDO2 script no
     longer runs `rm /etc/fido2`.
   - The fingerprint message becomes "turn off `services.fprintd`;
     `fprintAuth` follows it". The stale comment at `default.nix:1447-1450`
     is corrected.
   - The two rows get plain-bash `when`s: fingerprint shows when
     `command -v fprintd-enroll >/dev/null`, and FIDO2 when
     `[[ -e /etc/fido2 ]]`.
8. **`setup.security.fingerprint`.** Its `sudo pacman -S` becomes the
   `services.fprintd.enable` line plus `exit 1`. The ledger's `pacman` field
   is removed.

   **Deviation from the spec, found by Codex and verified:** the guard
   around that line, `if omarchy-pkg-missing libfprint-git fprintd usbutils`
   (`$T/bin/omarchy-setup-security-fingerprint:24`), is always true here.
   nixarchy's `omarchy-pkg-missing` (`pkgs/omarchy/nix-bin/omarchy-pkg-missing`)
   asks whether a *command* of that name exists, and `libfprint-git` never is
   one. So the spec's change alone would stop every run before `fprintd-enroll`,
   even with `services.fprintd` on. The plan also replaces the guard with
   `if ! command -v fprintd-enroll >/dev/null 2>&1; then`, so enrollment is
   reached once fprintd is on. The owner confirms this at plan review.
9. **Timezone.** `omarchy-menu-timezone` keeps the picker. At its
   `sudo timedatectl` line it sends a notification with
   `time.timeZone = "<tz>";` and exits 1, so the clock refresh and the
   success notification are no longer reached. Ledger row 344-347 is
   corrected.
10. **Battle.net: no change**, apart from its menu-exceptions reason
    (decision 15). Whether its confirm wording is right is an upstream
    question, pending the owner.
11. **Class 3.** These go to the route nixarchy already has:
    - `install.gaming.geforce-now` becomes `nixarchy-service-enable
      geforce-now`.
    - `install.ai.ollama` runs `setup.local-ai`'s action.
    - `omarchy-install-font` opens a floating terminal, but only on the
      missing-font path when stdout is not a terminal.
    - `update.firmware`: no change.
12. **Class 4 rows are hidden** with `when = "false"`: `install.windows`,
    `remove.windows`, `trigger.hardware.hybrid-gpu`, `setup.direct-boot`,
    `install.ai.hermes`, `install.ai.perplexity`, `remove.ai.hermes`,
    `remove.ai.perplexity` and `remove.browser.brave-origin`. The three
    existing `disabled` "Not available" Install rows are left alone. So are
    passwordless-sudo, plymouth and unlock.
13. **Ordering with #1301: either may land first.** #1301 hides every upstream
    `remove.*` row with an `omarchy-pkg-*` guard that nixarchy does not
    override, and every `when` written here is plain bash. `disabled` is
    honoured only after #1301, which is why class 4 hides rather than dims.
14. **The probe.** `checks.menu-actions` follows every visible action into its
    scripts, and every hazardous row needs a reason in `data/menu-actions.nix`.
    - A `hidden:` reason asserts the row's `when` is `false`.
    - A `guidance:` reason is permanent, for scripts that explain and exit
      before their writers.
    - `pending #1304 class N` is temporary, and Part 4 forbids it.
    - The probe proves that every hazardous row is classified. It does not
      prove a row is safe: `checks.remove-preinstalls` and
      `checks.menu-guidance` do that.
15. **Records.** `data/bin-ledger.nix` and `data/menu-exceptions.nix` are
    corrected in the Part whose change makes them true.

    **Deviation from the spec, decided by reading the code:** spec decision 15
    left it open whether rows leave `menu-exceptions.nix` once they are
    overridden. They do not. `tests/coverage.py:22-27` counts a row as known
    only if it is in `data/apps.nix`, in `data/services.nix` (its `menuId`s,
    `tests/options.nix:2299-2303`), or in `menu-exceptions.nix`. An override
    is not counted. So every touched Install row **stays** in
    `menu-exceptions.nix`, and only its reason changes.

**Coexistence (§14):** no NixOS option is set or changed, so no fixture
applies.

### Repo traps (named again at each step)

- **T-add:** a new file must be `git add`ed before nix sees it. It fails with
  "does not exist", not with "untracked".
- **T-fmt:** after any `.nix` edit, run `nix fmt`, then read `git diff --stat`.
  The nixpkgs-fmt hook can reformat a whole file.
- **T-heredoc:** no heredoc inside a Nix `''…''` string; use `printf`. Inside
  `''…''`, a literal `${` must be written `''${`. A plain `$VAR` needs no
  escaping. Two single quotes in a row (`''`) end the Nix string, so write an
  empty shell string as `""`, never `''`.
- **T-pipe:** use `set -o pipefail`, or don't pipe a command whose status you
  need. `cmd | tail` reports tail's status.
- **T-env:** a sandbox has no `/usr/bin/env`, so run tree scripts as
  `bash <file>`. A new `.github/scripts/*.py` starts with
  `#!/usr/bin/env python3` and is run as `python3 <file>`.
- **T-break:** after a §1 break, check that it landed with `git diff`. Restore
  with `git checkout HEAD -- <path>`, never `git checkout -- <path>`, which
  restores the index.
- **T-tier:** builds follow §6.
  - Cheap checks (`runCommand`, eval-only) run one at a time:
    `flock /mnt/data/vmtest/codex-build.lock nix build …`.
  - The `omarchy` package needs
    `pgrep -fc '^(nix build|nh os build|nixos-rebuild).*p620'` to print `0`,
    and a 1-minute load below 12.
  - `checks.options`, `checks.session` and every VM check: only when
    `gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`
    prints `0`; otherwise leave them to CI.
- **T-drv:** evaluate first, then build what you evaluated:
  `d=$(nix eval --raw .#checks.x86_64-linux.<n>.drvPath)`, then
  `flock … nix build "$d^*" --print-build-logs`. That way a background
  evaluation can't build a stale derivation.
- **T-commit:** `installer/mkFlake.nix` needs a committed tree. Nothing here
  builds installer checks, but commit before any check that pulls the
  flake template.
- **T-find:** use `find -L` on `result` links.
- **T-unfree:** prefix with `env -u NIXPKGS_ALLOW_UNFREE` if a step asks
  whether something evaluates with unfree off. None here does.

---

## Steps

### Part 1: class 1, data loss (branch `fix/1304-menu-arch-only-actions`)

**1.1 Write the probe script, and measure. Stop if it flags most of the
menu.**
File: new `.github/scripts/check-menu-actions.py`. Write exactly this:

```python
#!/usr/bin/env python3
"""Every visible menu row, followed into the scripts its action runs (#1304).

A row's action is a shell string. It is scanned itself, and every omarchy-*
command it names is followed through the shipped bin directory, transitively.
Each hit is a hazard group: check-bin-ledger.py's PATTERNS, pacman/yay,
omarchy-pkg-drop, or an rm into the home directory. Every row that reaches one
needs a reason in data/menu-actions.nix, and an entry whose row no longer
reaches anything is stale. That proves every hazardous row was classified,
not that any row is safe: an rm through a variable, or a guard in front of a
writer, is invisible here. nixarchy-* commands are generated by modules and
are not in the tree, so they are not followed.
"""
import argparse
import importlib.util
import json
import os
import re
import sys

# The menu has ~400 rows; far fewer with an action means the wrong file.
FLOOR = 300
CMD = re.compile(r"(?<![\w./-])omarchy-[a-z0-9-]+")


def load(path):
    spec = importlib.util.spec_from_file_location("bin_ledger", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def strip_jsonc(raw):
    # The same two transformations MenuModel.js applies.
    raw = re.sub(r"^\s*//[^\n]*(\n|$)", "", raw, flags=re.M)
    return re.sub(r",(\s*[}\]])", r"\1", raw)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--menu", required=True)
    ap.add_argument("--bin", required=True)
    ap.add_argument("--ledger-script", required=True)
    ap.add_argument("--entries")
    ap.add_argument("--measure", action="store_true")
    ap.add_argument("--no-pending", action="store_true")
    a = ap.parse_args()

    ledger = load(a.ledger_script)
    groups = dict(ledger.PATTERNS)
    groups["pacman"] = ledger.PACMAN
    groups["pkg-drop"] = re.compile(r"\bomarchy-pkg-drop\b")
    groups["home-rm"] = re.compile(r"\brm\b[^\n]*(?:~/|\$HOME/|\$\{HOME\}/)")

    cache = {}

    def body(name):
        if name not in cache:
            try:
                with open(os.path.join(a.bin, name), encoding="utf-8", errors="replace") as h:
                    cache[name] = ledger.strip_comments(h.read())
            except OSError:
                cache[name] = None
        return cache[name]

    def walk(action):
        found = {}  # group -> where it was first seen
        seen = set()
        stack = [(action, "action")]
        while stack:
            text, where = stack.pop()
            for group, rx in groups.items():
                if group not in found and rx.search(text):
                    found[group] = where
            for cmd in sorted(set(CMD.findall(text))):
                if cmd not in seen:
                    seen.add(cmd)
                    t = body(cmd)
                    if t is not None:
                        stack.append((t, cmd))
        return found

    def fmt(found):
        by = {}
        for group, where in found.items():
            by.setdefault(where, []).append(group)
        return "; ".join(f"{w}: {', '.join(sorted(g))}" for w, g in sorted(by.items()))

    menu = json.loads(strip_jsonc(open(a.menu, encoding="utf-8").read()))
    flagged, hidden, rows = {}, set(), 0
    for rid, row in menu.items():
        action = row.get("action")
        if not action:
            continue
        rows += 1
        if str(row.get("when", "")).strip() == "false":
            hidden.add(rid)
            continue
        found = walk(str(action))
        if found:
            flagged[rid] = found
    if rows < FLOOR:
        sys.exit(f"menu-actions: only {rows} rows with an action; is {a.menu} the generated menu?")
    summary = f"menu-actions: {rows} rows with an action, {len(flagged)} flagged, {len(hidden)} hidden"

    if a.measure:
        for rid in sorted(flagged):
            print(f"{rid}\t{fmt(flagged[rid])}")
        print(summary)
        return 0

    entries = json.load(open(a.entries, encoding="utf-8"))
    errors = []
    for rid in sorted(flagged):
        if rid not in entries:
            errors.append(f"{rid} reaches {fmt(flagged[rid])}, with no entry in data/menu-actions.nix")
    for rid, reason in sorted(entries.items()):
        if not isinstance(reason, str) or not reason.strip():
            errors.append(f"entry for {rid} has no reason")
            continue
        if reason.startswith("hidden:"):
            when = str(menu.get(rid, {}).get("when", "<no such row>"))
            if when.strip() != "false":
                errors.append(f"{rid} is listed hidden but its when is {when!r}")
        elif rid not in flagged:
            errors.append(f"entry for {rid}, which reaches no hazard: stale")
        if a.no_pending and reason.startswith("pending"):
            errors.append(f"pending reason left after the series: {rid}")
    if errors:
        print("\n".join("menu-actions: " + e for e in errors), file=sys.stderr)
        return 1
    print(summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

Measure against what is deployed (no build):

```bash
set -o pipefail
S=/mnt/data/vmtest/wt-1304
python3 $S/.github/scripts/check-menu-actions.py --measure \
  --menu /etc/nixarchy/omarchy-menu.jsonc \
  --bin /nix/store/rla9km5silzbp6h9dcfz0pd1p90ia8r9-nixarchy-omarchy-tree/bin \
  --ledger-script $S/.github/scripts/check-bin-ledger.py > /mnt/data/vmtest/1304-measure.txt
tail -1 /mnt/data/vmtest/1304-measure.txt
```

→ Verify by reading the last line, which says `N rows with an action, F
flagged`.

- **If F > N/2: STOP.** Report the file to the lead without writing any entry.
- **Otherwise:** keep the file, because 1.6 classifies from it. Codex
  estimated 74 of 398.

Traps: T-pipe, T-env (the script is run as `python3 <file>`), T-add (it is a
new file).

**1.2 The sibling rule in the generator.**
File: `modules/apps.nix`. Insert the code below after line 1004, which closes
the existing `overrides[row_id] = {…}` block, and before `out = {}`
(`:1006`). It is inside the `''…''` string, at the same indentation as the
loop above it.

```python
        # A Remove row whose Install sibling nixarchy rewired to the selection
        # undoes it the same way, whatever upstream's `when` spelled (#1304).
        # Runs after the pkg-present rule, so rows that rule mapped keep theirs.
        for row_id in list(upstream):
            if not row_id.startswith("remove.") or row_id in overrides:
                continue
            sibling = overrides.get("install." + row_id[len("remove."):], {})
            m = re.fullmatch(
                r"nixarchy-(app|service)-enable ([a-z0-9._-]+)",
                str(sibling.get("action", "")),
            )
            if not m:
                continue
            kind, ident = m.groups()
            if kind == "app":
                when = ("grep -qE '^[[:space:]]*" + ident
                        + "\\.enable' $HOME/.config/nixarchy/apps.nix")
                description = "Remove from your app selection, then Apply changes"
            else:
                when = ("grep -qE '^[[:space:]]*[^#[:space:]].*#@ " + ident
                        + "([[:space:]]|$)' $HOME/.config/nixarchy/services.nix")
                description = "Remove from your services, then Apply changes"
            overrides[row_id] = {
                "action": f"nixarchy-{kind}-disable {ident}",
                "when": when,
                "description": description,
            }
            print(f"sibling rule: {row_id} -> nixarchy-{kind}-disable {ident}")
```

→ Verify:

```bash
nix fmt
git diff --stat
d=$(nix eval --raw .#nixosConfigurations.reference.config.environment.etc.'"nixarchy/omarchy-menu.jsonc"'.source.drvPath)
flock /mnt/data/vmtest/codex-build.lock nix build "$d^*" --print-build-logs --out-link /mnt/data/vmtest/1304-menu
m=/mnt/data/vmtest/1304-menu
grep -A3 '"remove.development.go"' "$m"
grep -A3 '"remove.service.tailscale"' "$m"
```

This is the "rebuild the menu" recipe that later steps refer to.

The two `grep`s must show `nixarchy-app-disable go` and
`nixarchy-service-disable tailscale`. The build log must print exactly 14
`sibling rule:` lines.

Traps:
- T-fmt.
- T-heredoc. The code has `$HOME` and `[[:space:]]` but no `${`, so it
  needs no escaping. `"\\.enable"` stays exactly as the existing rule writes
  it (`:1001-1002`).
- The menu build evaluates `reference`: that is evaluation plus a small
  `runCommand`, so it is the cheap tier.

**1.3 Hide Phoenix's Remove row.**
File: `modules/apps.nix`. Before the closing `}` of the `overrideSpec`
literal at `:846`, after the `"trigger.vm-list"` entry, add:

```nix
        # #1304: hidden. Its omarchy-remove-dev-env arm is `elixir|phoenix`, so
        # removing Phoenix uninstalls Elixir and Erlang with it.
        "remove.development.elixir.phoenix".when = "false";
```

→ Verify: rebuild the menu as in 1.2, then
`grep -A4 '"remove.development.elixir.phoenix"' "$m"` must show
`"when": "false"`.

Traps: T-fmt.

**1.4 Replace `omarchy-remove-preinstalls`.**
File: new `pkgs/omarchy/nix-bin/omarchy-remove-preinstalls`, mode 755.
Write exactly this:

```bash
#!/usr/bin/env bash

# omarchy:summary=Remove preinstalled Omarchy applications (web apps, TUIs, and selected packages).

# Upstream deletes every web app and TUI launcher and rm -f's a list of names
# in ~/.local/bin, whoever made them (#1304). This deletes a path only after
# showing that Omarchy seeded it, one path at a time.
set -uo pipefail

apps="$HOME/.local/share/applications"
bindir="$HOME/.local/bin"

# Exactly the four lines omarchy-mise-install writes for this command name,
# and nothing else: same package on lines 3 and 4, and the file's own name as
# the binary (its bin defaults to the command).
is_mise_stub() {
  local f=$1 cmd=$2 pkg
  local -a l
  [[ -f $f && ! -L $f ]] || return 1
  mapfile -t -n 5 l <"$f"
  ((${#l[@]} == 4)) || return 1
  [[ ${l[0]} == '#!/bin/bash' && ${l[1]} == 'export MISE_MINIMUM_RELEASE_AGE=0' ]] || return 1
  [[ ${l[2]} == 'mise use -g --quiet '*' || exit 1' ]] || return 1
  pkg=${l[2]#mise use -g --quiet }
  pkg=${pkg% || exit 1}
  [[ ${l[3]} == "exec mise x $pkg -- \"$cmd\" \"\$@\"" ]]
}

if gum confirm "Are you sure you want to remove all preinstalled web apps, TUI wrappers, and desktop applications?"; then
  echo -e "Removing preinstalled Omarchy applications...\n"
  removed=()
  kept=()

  for src in "$OMARCHY_PATH"/applications/*.desktop; do
    dst=$apps/${src##*/}
    grep -qE '^Exec=(omarchy-launch-webapp|omarchy-webapp-handler|xdg-terminal-exec --app-id=TUI\.)' "$src" || continue
    [[ -e $dst || -L $dst ]] || continue
    if [[ -f $dst && ! -L $dst ]] && cmp -s "$src" "$dst"; then
      rm -f "$dst" && removed+=("$dst")
    else
      kept+=("$dst (changed since Omarchy installed it, or not a plain file)")
    fi
  done

  mkdir -p ~/.local/state/omarchy
  touch ~/.local/state/omarchy/preinstalls-removed
  hyprctl reload

  for cmd in codex claude gemini copilot gh opencode playwright playwright-cli \
    pi omp grok crush ghui hunk cursor-agent muse; do
    f=$bindir/$cmd
    [[ -e $f || -L $f ]] || continue
    if is_mise_stub "$f" "$cmd"; then
      rm -f "$f" && removed+=("$f")
    else
      kept+=("$f (not an Omarchy mise launcher)")
    fi
  done

  # Only the wrapper omarchy-install-hermes-cli wrote is a preinstall.
  if omarchy-install-hermes-cli --owns; then
    rm -f "$bindir/hermes" && removed+=("$bindir/hermes")
  fi

  if omarchy-cmd-present update-desktop-database; then
    update-desktop-database "$apps" &>/dev/null || true
  fi

  ((${#removed[@]})) && printf 'Removed %s\n' "${removed[@]}"
  ((${#kept[@]})) && printf 'Kept    %s\n' "${kept[@]}"
  echo
  echo "The preinstalled packages are part of your app selection here:"
  echo "remove them under Remove > App / package, then Apply changes."
fi
```

→ Verify: `bash -n pkgs/omarchy/nix-bin/omarchy-remove-preinstalls`.

Traps: T-add, and keep the `# omarchy:summary=` line (`default.nix:1099`).
`cmp` is diffutils, which a NixOS system always has; no `runtimeInputs`
apply to tree scripts.

**1.5 Replace `omarchy-install-preinstalls`.**
File: new `pkgs/omarchy/nix-bin/omarchy-install-preinstalls`, mode 755.

```bash
#!/usr/bin/env bash

# omarchy:summary=Restore the preinstalled Omarchy applications (web apps, TUIs, and selected packages).

# Upstream reseeds with omarchy-refresh-applications, whose cp -f replaces an
# edited launcher or a home-manager link and whose mise stubs delete a
# home-manager ~/.local/bin entry, then omarchy-pkg-add exits 1 here, so the
# marker never cleared (#1304). This only adds what is missing.
set -uo pipefail

apps="$HOME/.local/share/applications"

if gum confirm "Are you sure you want to restore all preinstalled web apps, TUI wrappers, and desktop applications?"; then
  echo -e "Restoring preinstalled Omarchy applications...\n"
  mkdir -p "$apps"
  for src in "$OMARCHY_PATH"/applications/*.desktop; do
    dst=$apps/${src##*/}
    [[ -e $dst || -L $dst ]] && continue
    cp --no-preserve=mode "$src" "$dst" && echo "Restored ${src##*/}"
  done
  if omarchy-cmd-present update-desktop-database; then
    update-desktop-database "$apps" &>/dev/null || true
  fi
  echo
  echo "The agent CLIs and the preinstalled packages are part of your app"
  echo "selection here: add them under Install, then Apply changes."
  rm -f ~/.local/state/omarchy/preinstalls-removed
  hyprctl reload
fi
```

→ Verify: `bash -n` on the new file.

Traps: T-add.

**1.6 Ledger rows, and `data/menu-actions.nix` from the measurement.**

- **`data/bin-ledger.nix`.** Add the two rows below, in alphabetical order
  among the `omarchy-install-*` and `omarchy-remove-*` rows:

```nix
  "omarchy-install-preinstalls" = {
    class = "replace";
    reason = "Upstream reseeds through omarchy-refresh-applications, whose cp -f replaces an edited launcher or a home-manager link and whose mise stubs delete a home-manager ~/.local/bin entry, then exits on omarchy-pkg-add so the marker never clears. Copies only missing launchers, writes no stubs, and clears the marker (#1304).";
  };
  "omarchy-remove-preinstalls" = {
    class = "replace";
    reason = "Upstream deletes every web app and TUI launcher and rm -f's named ~/.local/bin entries whoever made them. Deletes only an unmodified, regular-file seed of a shipped web app or TUI, and only an exact omarchy-mise-install stub (#1304).";
  };
```

  Then replace the `omarchy-pkg-drop` row's `reason` and `pacman` (`:379-383`)
  with:

```nix
    reason = "Vendored unchanged. Reached from live menu rows; its pacman -Qq comes back empty here, so it drops nothing.";
    pacman = "Reached, and inert: `pacman -Qq` answers nothing on NixOS, so the -Rns branch never runs.";
```

- **New `data/menu-actions.nix`.** It is an attribute set of
  `"<row id>" = "<reason>";`, with a header comment of no more than 6 lines
  pointing at `tests/menu-actions.nix`. Write one entry for every row in
  `/mnt/data/vmtest/1304-measure.txt` **after** applying 1.2 to 1.5. Re-run
  1.1's measurement against the newly built menu (1.7's `menu`) and tree,
  because the sibling rule removes the 14 rewired rows. The tree is the
  package build: `t=$(flock /mnt/data/vmtest/codex-build.lock nix build --print-out-paths .#packages.x86_64-linux.omarchy)`,
  with `--bin "$t/share/omarchy/bin"` and `--menu /mnt/data/vmtest/1304-menu`
  (T-tier package rule). Pick each reason from
  this table, in order, and take the first that fits:

| the row | reason text |
|---|---|
| `remove.preinstalls` | **no entry.** After 1.4 the replacement deletes only through variables (`rm -f "$dst"`), which the probe cannot see, so the row is not flagged. Its safety is `checks.remove-preinstalls`. An entry here would be reported stale |
| `install.preinstalls` | `owned: adds missing launchers only, never overwrites; its one rm is its own marker (decision 2, checks.remove-preinstalls)`. Its `rm -f ~/.local/state/…` matches `home-rm` |
| the DNS rows, `setup/remove.security.sshd`, `setup/remove.security.sudoless-docker`, `remove.security.fingerprint`/`fido2`, `setup.security.fingerprint`, `update.timezone` | `pending #1304 class 2: decision <4…9>` |
| the rows decision 12 lists, if flagged | `pending #1304 class 4: decision 12` |
| `install.gaming.geforce-now`, `install.ai.ollama`, fonts, if flagged | `pending #1304 class 3: decision 11` |
| the row acts only on what the user picked (for example `remove.webapp`, `remove.tui`, `remove.theme`) | `user-chosen: <one line on what it deletes>` |
| the row deletes only its own data, behind its own confirm (for example `remove.gaming.battlenet`) | `owned: <one line>` |
| the hit is a `systemctl --user` or a user unit | `session: <one line>` |
| the hit is on a branch the row does not take (for example the default-agent rows reaching an OpenClaw branch) | `unreached: <which branch, and why the row never takes it>` |

  **Any flagged row that fits none of these is a defect outside the spec.
  STOP**, and report the row and its hazard line to the lead. Do not
  invent a fix.

  **Pre-classified.** The planner ran this step's script read-only against
  the deployed menu and tree: 335 rows with an action, **74 flagged**, and 2
  hidden. After 1.2 to 1.5 the 13 dev rows, `remove.service.tailscale` and
  `remove.preinstalls` drop out, and Phoenix becomes hidden. Use these
  reasons. A row that is flagged and not listed here is the STOP case.

| rows | flagged by | reason |
|---|---|---|
| `remove.development.elixir.phoenix` (now hidden) | — | `hidden: its elixir\|phoenix arm removes Elixir and Erlang (decision 3)` |
| `remove.development.rails`, `remove.development.php.laravel` | `omarchy-remove-dev-env: home-rm, pacman` | `unreached: the pacman lines are the php and symfony arms, which the generator overrides; rails removes its own mise Ruby and ~/.gemrc, laravel its composer package (decision 3)` |
| `install.preinstalls` | `omarchy-install-preinstalls: home-rm` | `owned: adds missing launchers only, never overwrites; its one rm is its own marker (decision 2, checks.remove-preinstalls)` |
| `remove.gaming.battlenet` | `home-rm, pkg-drop` | `owned: deletes its own prefix; GE-Proton and umu only after a confirm; pkg-drop is inert here (decision 10)` |
| `install.style.theme`, `style.theme` | `omarchy-install-hermes-cli: home-rm` | `owned: omarchy-install-hermes-cli removes only the wrapper it wrote (--owns)` |
| `setup.security.fido2` | `omarchy-remove-security-fido2: pkg-drop` (it names the Remove command in its guidance) | `unreached: names omarchy-remove-security-fido2 in its guidance text and never runs it` |
| `update.firmware` | `omarchy-update-firmware: boot-write` | `unreached: the /boot install runs only if /usr/lib/fwupd/efi/fwupdx64.efi exists, which it never does here (decision 11)` |
| the 6 `install.style.font.*`, `update.config.shell`, `update.process.shell` | `omarchy-restart-shell: systemctl-user` | `session: restarts the user's shell unit` |
| the 14 `setup.default.agent.*` | `omarchy-launch-openclaw: systemctl-user` | `session: the OpenClaw branch starts a user unit; other agents never take it` |
| `setup.config.xcompose`, `trigger.reminder.{set,show,clear}`, `trigger.toggle.crash-capture`, `update.hardware.audio` | `systemctl-user` | `session: <the user unit it restarts or toggles>` |
| `update.hardware.bluetooth`, `update.hardware.wifi`, `update.hardware.trackpad` | `rfkill`, `nmcli-radio`, `modprobe` | `runtime: resets <device> for this boot; nothing a rebuild owns` |
| the 4 `setup.network.dns.*`, `setup.security.sshd`, `remove.security.sshd`, both `*.security.sudoless-docker`, `remove.security.fingerprint`, `remove.security.fido2`, `setup.security.fingerprint`, `update.timezone` | various | `pending #1304 class 2: decision <4…9>` |
| `install.windows`, `remove.windows`, `trigger.hardware.hybrid-gpu`, `install.ai.hermes`, `remove.ai.hermes`, `remove.ai.perplexity`, `remove.browser.brave-origin` | various | `pending #1304 class 4: decision 12` |

  The `runtime:` and `unreached:` prefixes are additions to the spec's set
  of `owned`, `user-chosen`, `session`, `guidance`, `hidden` and `pending`.
  The check gives no prefix a meaning except `hidden:` and `pending`.

→ Verify: `nix eval --json --file data/menu-actions.nix | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))'`.

Traps: T-add for `data/menu-actions.nix`, T-fmt.

**1.7 `checks.menu-actions`.**
New file `tests/menu-actions.nix`:

```nix
{ inputs, pkgs }:
# Every visible menu row's action, followed into the scripts it runs, against
# the reasons in data/menu-actions.nix (#1304). See
# .github/scripts/check-menu-actions.py for what it can and cannot see.
let
  # The same machine menu-verbs reads, so both checks see the same rows.
  eval = inputs.self.nixosConfigurations.reference.extendModules {
    modules = [
      {
        programs.nixarchy.services.boxes.enable = true;
        programs.nixarchy.services.devenv.enable = true;
      }
    ];
  };
  shipped = pkgs.nixarchy-omarchy or pkgs.omarchy;
in
pkgs.runCommand "nixarchy-menu-actions"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    menu = eval.config.environment.etc."nixarchy/omarchy-menu.jsonc".source;
    bin = "${shipped}/share/omarchy/bin";
    entries = pkgs.writeText "menu-actions.json" (builtins.toJSON (import ../data/menu-actions.nix));
    script = ../.github/scripts/check-menu-actions.py;
    ledger = ../.github/scripts/check-bin-ledger.py;
  }
  ''
    python3 $script --menu "$menu" --bin "$bin" --entries "$entries" --ledger-script "$ledger"
    touch $out
  ''
```

Register it in `flake.nix`'s `uniformChecks` list (`:1873-2045`), in
alphabetical order next to `"menu-verbs"` (`:1985`), with a two-line comment:
`# Every visible menu row's action, followed into its scripts (#1304).`

→ Verify:

```bash
git add tests/menu-actions.nix data/menu-actions.nix .github/scripts/check-menu-actions.py
d=$(nix eval --raw .#checks.x86_64-linux.menu-actions.drvPath)
flock /mnt/data/vmtest/codex-build.lock nix build "$d^*" --print-build-logs
```

It must end with `menu-actions: N rows with an action, F flagged, H hidden`.

Traps:
- T-add, T-fmt, T-drv.
- This builds the `omarchy` package, so check the T-tier package condition
  before running it.

**1.8 `checks.remove-preinstalls`, the data-loss guard.**
New file `tests/remove-preinstalls.nix`, registered in `uniformChecks` in
alphabetical order. It is a `runCommand` with
`nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.diffutils pkgs.findutils pkgs.gnugrep pkgs.gnused ]`.
The derivation has these attributes:
- `tree = "${shipped}/share/omarchy"`, with `shipped` as in 1.7;
- `upstream = inputs.omarchy`;
- `remove`, `restore`: the scripts under test. They default to
  `"${tree}/bin/omarchy-remove-preinstalls"` and
  `"${tree}/bin/omarchy-install-preinstalls"`.

Its build script, all `printf`, no heredoc (T-heredoc). Escape every
literal `${` inside the Nix string as `''${`.

1. **Isolation.** `set -euo pipefail; real_home=$HOME` (in the sandbox this
   is `/homeless-shelter`). Then export `HOME=$TMPDIR/home`, and put
   `XDG_DATA_HOME`, `XDG_STATE_HOME`, `XDG_CONFIG_HOME` and `XDG_CACHE_HOME`
   under `$HOME/.local/share`, `.local/state`, `.config` and `.cache`. Export
   `OMARCHY_PATH=$tree`.
2. **Stubs** in `$TMPDIR/stubs`, written with `printf`. Each appends
   `<name> <args>` to `$TMPDIR/calls`:
   - `gum`, `hyprctl`, `update-desktop-database` and `mise`, which exit 0;
   - `omarchy-install-hermes-cli`, which exits 1, meaning "does not own";
   - `pacman`, which prints `error: pacman is not on NixOS` to stderr and
     exits 1. That is the contract of `pkgs/omarchy/pacman-shim.sh`.

   Set `PATH=$TMPDIR/stubs:$tree/bin:$PATH`.
3. **Pin the stub shape.** Extract the heredoc body from
   `$tree/bin/omarchy-mise-install` with
   `sed -n '/<<EOF$/,/^EOF$/p' | sed '1d;$d'`. It must be exactly 4 lines:
   - line 1 `#!/bin/bash`
   - line 2 `export MISE_MINIMUM_RELEASE_AGE=0`
   - line 3 `mise use -g --quiet $package_arg || exit 1`
   - line 4 `exec mise x $package_arg -- $bin_arg "\$@"`

   Otherwise fail with
   `omarchy-mise-install's stub shape changed; update is_mise_stub in nix-bin/omarchy-remove-preinstalls`.
4. **Fixture** (`A=$HOME/.local/share/applications`, `B=$HOME/.local/bin`,
   `HM=$TMPDIR/hm`):
   - `cp $tree/applications/YouTube.desktop $A/`, which must be **deleted**;
   - `cp $tree/applications/mpv.desktop $A/`, **kept**;
   - `sed 's|https://launchpad.37signals.com|https://example.org/bc|'
     $tree/applications/Basecamp.desktop > $A/Basecamp.desktop`, **kept**;
   - `$A/MyApp.desktop` =
     `[Desktop Entry]\nName=MyApp\nExec=omarchy-launch-webapp https://example.org\n`,
     **kept**;
   - `$A/MyTui.desktop` =
     `[Desktop Entry]\nName=MyTui\nExec=xdg-terminal-exec --app-id=TUI.mytui -e htop\n`,
     **kept**;
   - `cp $tree/applications/Zoom.desktop $HM/Zoom.desktop` and
     `ln -s $HM/Zoom.desktop $A/Zoom.desktop`, **kept**;
   - `stub() { printf '#!/bin/bash\nexport MISE_MINIMUM_RELEASE_AGE=0\nmise use -g --quiet "%s" || exit 1\nexec mise x "%s" -- "%s" "$@"\n' "$1" "$1" "$1"; }`;
   - `stub claude > $HM/claude; ln -s $HM/claude $B/claude`, **kept**;
   - `stub codex > $B/codex`, **deleted**;
   - `$B/gemini` = `#!/bin/bash\n# my wrapper\nmise use -g --quiet "gemini" || exit 1\nexec mise x "gemini" -- "gemini" --model x "$@"\n`,
     **kept**;
   - `$B/gh` = `#!/bin/bash\nexec /opt/gh "$@"\n`, **kept**;
   - `$B/opencode`: stub-shaped, but for another binary,
     `#!/bin/bash\nexport MISE_MINIMUM_RELEASE_AGE=0\nmise use -g --quiet "foo" || exit 1\nexec mise x "foo" -- "bar" "$@"\n`,
     **kept**.
5. **State, exactly this code.** Shipped launchers have spaces in their
   names (`Google Maps.desktop`, `Disk Usage.desktop`), so the path is a
   tab-separated first field and never split on spaces:

   ```bash
   state() {
     (cd "$TMPDIR" && find home hm \( -type f -o -type l \) -print0 | sort -z) |
       while IFS= read -r -d "" p; do
         if [ -L "$TMPDIR/$p" ]; then
           printf '%s\tL %s\n' "$p" "$(readlink "$TMPDIR/$p")"
         else
           printf '%s\tF %s\n' "$p" "$(sha256sum <"$TMPDIR/$p" | cut -d" " -f1)"
         fi
       done
   }
   # D/C/A<TAB>path, one per line, sorted: deleted, changed, added.
   compare() {
     awk -F '\t' 'NR == FNR { b[$1] = $2; next } { a[$1] = $2 }
       END {
         for (p in b) if (!(p in a)) print "D\t" p; else if (b[p] != a[p]) print "C\t" p
         for (p in a) if (!(p in b)) print "A\t" p
       }' "$1" "$2" | sort
   }
   pick() { grep "^$1"$'\t' "$2" | cut -f2- || true; }  # paths of one kind, one per line
   ```

   Write `state > before`, run the script, then `state > after`, and
   `compare before after > delta`. A list in a message is
   `pick D delta | paste -sd ' '`. Compare lists as newline-separated text,
   for example `[ "$(pick D delta)" = "$expected" ]` with `expected` built by
   `printf '%s\n' … | sort`. Every snippet sits inside the Nix `''` string:
   it has no `${` and no `''`, so it needs no escaping.
6. **Remove run.** Run `state > before`, then `rc=0; bash "$remove" >log 2>&1 || rc=$?`,
   then `state > after` and `compare before after > delta`. Check **every**
   row of the table below, collecting each failure message, then print them
   all and `exit 1` if there were any. A §1 break then shows every symptom,
   not just the first:

   | must hold | otherwise fail with |
   |---|---|
   | `rc` is 0 | `remove exited $rc` |
   | `deleted` is exactly `home/.local/bin/codex home/.local/share/applications/YouTube.desktop` | `deleted files that are not preinstalls: <deleted minus expected>`; for the opposite case, `left preinstalls in place: <expected minus deleted>` |
   | `changed` is empty | `changed files it should not touch: <list>` |
   | `added` is exactly `home/.local/state/omarchy/preinstalls-removed` | `wrote unexpected files: <list>` |
   | `real_home` does not exist | `wrote outside the fixture: $real_home` |

   Each list is sorted and space-joined.
7. **Restore run**, starting from that end state, in the same way:
   `state > before`, then `bash "$restore"`, then `state > after`, then
   `compare`. Collect every failure, as in 6. These must hold:

   | must hold | otherwise fail with |
   |---|---|
   | the marker is gone | `preinstalls-removed still present after Restore` |
   | `home/.local/share/applications/YouTube.desktop` is back and identical to the shipped copy | `Restore did not bring back YouTube.desktop` |
   | `changed` is empty | `Restore changed files it should not touch: <list>` |
   | every addition is under `home/.local/share/applications/` | `Restore wrote unexpected files: <list>` |
   | `real_home` still does not exist | `wrote outside the fixture: $real_home` |

   The additions are the shipped launchers that were missing.
8. `touch $out`.

→ Verify:

```bash
git add tests/remove-preinstalls.nix
d=$(nix eval --raw .#checks.x86_64-linux.remove-preinstalls.drvPath)
flock /mnt/data/vmtest/codex-build.lock nix build "$d^*" --print-build-logs
```

It must go green.

Traps: T-add, T-heredoc, T-pipe, T-env (run `bash "$remove"`; never execute
the file directly), T-fmt, T-drv.

**1.9 Run the existing checks this Part touches.**

```bash
for c in bin-ledger patched-files menu-verbs menu-actions remove-preinstalls; do
  d=$(nix eval --raw .#checks.x86_64-linux.$c.drvPath)
  flock /mnt/data/vmtest/codex-build.lock nix build "$d^*" --print-build-logs || break
done
```

Then `nix fmt -- --ci`, `nix run nixpkgs#statix -- check .` and
`nix run nixpkgs#deadnix -- --fail .`.

- `checks.options` (which runs `tests/coverage.py`) and `checks.session` run
  only under the T-tier VM rule. Otherwise leave them to CI, and say so in
  the PR.
- `session.nix:1514` runs `omarchy-install-font` (Part 4) and
  `session.nix:1824` names `omarchy-dns` (Part 2). Neither is touched in
  Part 1.

Traps: T-tier, T-drv. Commit before this step:
`git commit -m "WIP baseline for the §1 proofs"`. Squash it in 1.12.

**1.10 §1 proofs (break, capture red, restore, green).** Every break is
verified with `git diff` before the check runs, and restored with
`git checkout HEAD -- <path>`. Save each red output to
`/mnt/data/vmtest/1304-p1-proof-<n>.txt`.

1. Delete the `"remove.gaming.battlenet"` line from `data/menu-actions.nix`,
   then `git add`, then build `menu-actions`. Expected red:
   `menu-actions: remove.gaming.battlenet reaches omarchy-remove-gaming-battlenet: home-rm, pkg-drop, …, with no entry in data/menu-actions.nix`.
   It uses `rm -f "$HOME/.local/share/applications/battlenet.desktop"` and
   `omarchy-pkg-drop umu-launcher`. Record the exact group list.

   This proof uses Battle.net rather than `remove.preinstalls` because the
   replaced Remove is not flagged at all, which is the probe's documented
   blind spot.
2. Comment out the sibling rule's whole `for` loop from 1.2, then build
   `menu-actions`. Expected red: 14 lines, one per rewired row, of the form
   `remove.development.<x> reaches omarchy-remove-dev-env: …` and
   `remove.service.tailscale reaches omarchy-remove-service-tailscale: …, with no entry`.
3. Add `"remove.development.go" = "pending #1304 class 1";` to
   `data/menu-actions.nix`. Expected red:
   `menu-actions: entry for remove.development.go, which reaches no hazard: stale`.
4. Change 1.3's `when = "false"` to `when = "true"`. Its `hidden:` entry is
   already in place from 1.6. Expected red:
   `menu-actions: remove.development.elixir.phoenix is listed hidden but its when is 'true'`.
5. In `tests/remove-preinstalls.nix`, set
   `remove = "${upstream}/bin/omarchy-remove-preinstalls"`. Expected red:
   `deleted files that are not preinstalls: home/.local/bin/claude home/.local/bin/gemini home/.local/bin/gh home/.local/share/applications/Basecamp.desktop home/.local/share/applications/MyApp.desktop home/.local/share/applications/MyTui.desktop home/.local/share/applications/Zoom.desktop`.
6. In the replacement script, change `[[ -f $f && ! -L $f ]]` in
   `is_mise_stub` to `[[ -f $f ]]`. Expected red:
   `deleted files that are not preinstalls: home/.local/bin/claude`.
7. Same, in the launcher branch: change
   `[[ -f $dst && ! -L $dst ]] && cmp -s` to `cmp -s`. Expected red: `…
   home/.local/share/applications/Zoom.desktop`.
8. Delete the `grep -qE '^Exec=(…)' "$src" || continue` line. Expected red:
   `… home/.local/share/applications/mpv.desktop`.
9. Replace the body of `is_mise_stub` with `grep -q 'mise use -g' "$1"`.
   Expected red: `… home/.local/bin/gemini home/.local/bin/opencode`. It may
   also include `home/.local/bin/claude`, because grep follows the link.
   Record what it says.
   9b. Restore, then delete only the last line of `is_mise_stub` (the
   `exec mise x $pkg -- "$cmd"` comparison), leaving the prefix checks.
   Expected red: `… home/.local/bin/opencode`.
10. Set `restore = "${upstream}/bin/omarchy-install-preinstalls"`. Expected
    red, all at once since failures are collected:
    - `preinstalls-removed still present after Restore`, because the
      replaced `omarchy-pkg-add` exits 1;
    - `Restore changed files it should not touch:`, with at least
      `home/.local/bin/claude` (a link that became a stub) and
      `home/.local/share/applications/Basecamp.desktop`;
    - `Restore wrote unexpected files:`, listing new stubs under
      `home/.local/bin/`.

    `Zoom.desktop` is **not** expected: `cp -f` writes through the link
    into `$HM/Zoom.desktop` with identical bytes. Record the exact output.

After each break: restore, rebuild, and confirm it is green. Paste all ten red
outputs into the PR.

Traps: T-break, T-add (an entries edit needs `git add` before the build),
T-drv. Breaks 5 to 10 rebuild only `remove-preinstalls`, except 6 to 9, which
edit `nix-bin` and so rebuild the `omarchy` package (T-tier).

**1.11 Write back.**
- **`tests/AGENTS.md`:** append a new section at the end (§0 of the root
  file: never insert one in the middle), titled
  `## menu-actions proves classification, not safety (#1304)`. In under 25
  lines it says:
  - what the walk follows;
  - that `nixarchy-*` commands and `rm "$VAR"` are invisible;
  - that patched-in-place scripts stay flagged and carry `guidance:`
    reasons;
  - that safety is the `runCommand` checks' job;
  - and the two holes the spec names: no check here proves that the stock
    menu hides a `when = "false"` row (that is MenuModel and #1301's
    `checks.menu-guards`), or that `nixarchy-service-disable geforce-now`
    stops activation from reinstalling the Flatpak.
- **Root `CLAUDE.md`, §1:** append one bullet. It says that `cmp` and
  `grep` follow symlinks, so an "unmodified seed" test passes a
  home-manager link to identical content, and that `-L` has to be tested
  first. The general lesson: a content test is not an ownership test.

→ Verify: `git diff --stat` shows only these two files changed in this step.

Traps: none.

**1.12 PR (only after the owner says to push).**
- Squash the baseline WIP away, so that one commit has the subject
  `Removing preinstalls deletes only what Omarchy seeded, and Remove
  Development undoes the Nix selection its Install row made`.
- Check `git merge-base origin/main HEAD` and `git show --stat HEAD`
  (§5, the `reset --soft` trap).
- The body follows `.github/pull_request_template.md`. It:
  - links the intent, the spec and this plan;
  - pastes the ten §1 outputs;
  - lists the checks left to CI;
  - says `Refs #1304`, not a closing keyword, because three Parts remain;
  - says which steps the coder did;
  - contains no skip-CI marker in literal form.

### Part 2: class 2, imperative writes (branch `fix/1304-menu-imperative-writes`, from `main` after Part 1 merges)

**2.1 Patches.**
File: `pkgs/omarchy/default.nix`. Insert a new block after the PAM drift
guard (`:1469-1472`), headed `# #1304: commands a menu row runs that can
only explain on NixOS. Each exits 1 before its first writer.` Every
replacement is a sequence of `echo … >&2` lines followed by `exit 1`, in the
style of the PAM patches at `:1452-1464`.

- **`omarchy-dns`**, anchor `'require_root "$provider"'` (exactly one match,
  at `$T/bin/omarchy-dns:259`). Text:

  ```
  echo "DNS is part of your NixOS configuration here, not a file to edit:" >&2
  echo "" >&2
  echo "  networking.nameservers = [ \"1.1.1.1\" \"1.0.0.1\" ];" >&2
  echo "  services.resolved.fallbackDns = [ \"9.9.9.9\" ];" >&2
  echo "" >&2
  echo "Add it to your host configuration, then Apply changes." >&2
  exit 1
  ```

- **`omarchy-setup-security-sudoless-docker`**, anchor
  `echo "⚠️  WARNING: Enabling sudoless Docker adds you to the 'docker' group."`.
  Text:
  - `Docker here is rootless by default: it runs as you and needs no group.`
  - `For the rooted daemon, the docker group is declared:`
  - `  users.users.<you>.extraGroups = [ "docker" ];`
  - `then Apply changes.`
  - `exit 1`
- **`omarchy-remove-security-sudoless-docker`**, anchor
  `echo "Removing $USER from the docker group..."`. Text:
  `The docker group is declared here: remove "docker" from users.users.<you>.extraGroups, then Apply changes.`,
  then `exit 1`.
- **`omarchy-remove-security-fingerprint`**, anchor
  `echo -e "\e[32mRemoving fingerprint scanner from authentication.\n\e[0m"`.
  Text:
  - `Fingerprint login is declared here. Turn off services.fprintd (fprintAuth follows it),`
  - `then Apply changes. Nothing on this machine was changed.`
  - `exit 1`
- **`omarchy-remove-security-fido2`**, anchor
  `echo -e "\e[32mRemoving FIDO2 device from authentication.\n\e[0m"`. Text:
  - `FIDO2 login is declared here. Remove security.pam.u2f and the u2fAuth lines,`
  - `Apply changes, and only then delete the registration: sudo rm -rf /etc/fido2.`
  - `Nothing on this machine was changed.`
  - `exit 1`
- **`omarchy-setup-security-fingerprint`**, two anchors in one
  `substituteInPlace` (the deviation under decision 8):
  - `if omarchy-pkg-missing libfprint-git fprintd usbutils; then` becomes
    `if ! command -v fprintd-enroll >/dev/null 2>&1; then`;
  - `  sudo pacman -S --needed --noconfirm --ask 4 libfprint-git fprintd usbutils`
    becomes
    `  echo "Enable the reader first: services.fprintd.enable = true; then Apply changes and run this again." >&2`,
    then `  exit 1`.

  The `echo "Installing required packages..."` line between them stays.
- **`omarchy-menu-timezone`**, anchor
  `sudo timedatectl set-timezone "$timezone"`. Text:
  `omarchy-notification-send "Timezone is part of your configuration: set time.timeZone = \"$timezone\"; then Apply changes"`,
  then `exit 1`. This makes `$T/bin/omarchy-menu-timezone:11-12`
  unreachable, which is decision 9.

The new early `exit 1` leaves upstream's later lines (`rm`, `omarchy-pkg-drop`,
and the existing PAM-patch `echo`s) in the file, unreachable. That is
deliberate: patching in place keeps each anchor small, and Part 2.4 gives
those rows a `guidance:` reason because the probe still sees the text.

Also, inside the existing fingerprint patch at `:1459-1464`, change
`Drop the fprintAuth lines and services.fprintd from` and
`your configuration and rebuild.` to
`Turn off services.fprintd (fprintAuth follows it)` and `and rebuild.`.
Fix the comment at `:1447-1450`: it should say that
`/etc/pam.d/omarchy-lock-fingerprint` is declared by `modules/nixos.nix`
when fprintd is on, so the removal no longer deletes it.

→ Verify:
- `nix fmt`, then `git diff --stat`.
- Build the omarchy package (T-tier).
- `grep -c 'Nothing on this machine was changed' result/share/omarchy/bin/omarchy-remove-security-f*`
  must print 1 for each file (`find -L` / T-find if you search).

Traps:
- T-heredoc. Every `"` inside a Nix `''` string is literal, `$timezone` needs
  no escaping, and `''${` is not used.
- `--replace-fail` throws if an anchor moved.
- T-tier.

**2.2 Ledger rows.**
File: `data/bin-ledger.nix`. Change these rows:

- `omarchy-dns` (`:229-233`): `class = "patch"`, and `reason` becomes `Writes
  resolved.conf and NetworkManager state imperatively; exits 1 with the
  networking.nameservers route at require_root, before any write (#1304).`
  Keep `allow = "etc-write"`.
- `omarchy-menu-timezone` (`:344-348`): `class = "patch"`, and `reason`
  becomes `timedatectl from a terminal-less menu row, with no sudoers rule,
  where time.timeZone is always set; notifies with the time.timeZone line
  and exits 1 (#1304).` Keep its `allow`.
- The sudoless-docker rows (`:505-509`, `:568-572`): `class = "patch"`, and
  the reasons name the extraGroups route. Keep `allow`.
- `omarchy-remove-security-fingerprint` and `omarchy-remove-security-fido2`
  (`:491-499`): add to each reason `and exits 1 before dropping packages or
  deleting the registration (#1304)`. Keep `allow`.
- `omarchy-setup-security-fingerprint` (`:558-562`): delete the `pacman =`
  line, and add `the pacman install becomes the services.fprintd.enable
  line (#1304)` to its reason.

→ Verify: build `checks.bin-ledger`. It must be green. If it says a row's
`allow` group is stale, delete only that group.

Traps: T-drv.

**2.3 Menu overrides.**
File: `modules/apps.nix`, in the `overrideSpec` literal, after 1.3's entry:

```nix
        # #1304: omarchy-dns now explains instead of switching, and these
        # three ran with no terminal to show it in.
        "setup.network.dns.dhcp".action = "omarchy-launch-floating-terminal-with-presentation 'omarchy-dns DHCP'";
        "setup.network.dns.cloudflare".action = "omarchy-launch-floating-terminal-with-presentation 'omarchy-dns Cloudflare'";
        "setup.network.dns.google".action = "omarchy-launch-floating-terminal-with-presentation 'omarchy-dns Google'";
        # #1304: the catalogue's openssh route, in its rows' shape. Setup dims
        # rather than hides: a negated grep on a missing services.nix is true.
        "setup.security.sshd" = {
          action = "nixarchy-service-enable openssh";
          disabled = "grep -qE '^[[:space:]]*[^#[:space:]].*#@ openssh([[:space:]]|$)' $HOME/.config/nixarchy/services.nix";
          description = "Turn on services.openssh in your services, then Apply changes";
        };
        "remove.security.sshd" = {
          action = "nixarchy-service-disable openssh";
          when = "grep -qE '^[[:space:]]*[^#[:space:]].*#@ openssh([[:space:]]|$)' $HOME/.config/nixarchy/services.nix";
          description = "Remove from your services, then Apply changes";
        };
        # #1304: plain bash, so #1301's rule for pkg-guarded rows leaves these alone.
        "remove.security.fingerprint".when = "command -v fprintd-enroll >/dev/null";
        "remove.security.fido2".when = "[[ -e /etc/fido2 ]]";
```

→ Verify:
- `nix fmt`, then `git diff --stat`.
- Rebuild the menu (1.2's commands). `grep -A3` each of the eight ids must
  show the new action or `when`.
- Check that `nix eval --raw .#nixosConfigurations.reference.config.environment.etc.'"nixarchy/omarchy-menu.jsonc"'.source`
  still evaluates.

Traps: T-fmt. If the eval says `attribute '…' already defined`, an id is
generated elsewhere (see Mechanisms). Stop and report it.

**2.4 `data/menu-actions.nix`.** For each `pending #1304 class 2` entry:

- **The row is still flagged** (the DNS rows, both sudoless-docker rows,
  `remove.security.fingerprint`, `remove.security.fido2`,
  `setup.security.fingerprint`, `update.timezone`): rewrite it as
  `guidance: exits 1 before its writers (decision <n>, checks.menu-guidance)`.
- **The row is no longer flagged** (the two sshd rows, now
  `nixarchy-service-*`): delete the entry.

→ Verify: build `menu-actions`. It must be green.

Traps: T-add if the file is new on this branch (it is not), T-drv.

**2.5 `checks.menu-guidance`.**
New file `tests/menu-guidance.nix`, registered in `uniformChecks`. It is a
`runCommand` over `${shipped}/share/omarchy/bin` (`shipped` as in 1.7), with
`nativeBuildInputs` from 1.8, `HOME` and every `XDG_*` var under `$TMPDIR`,
and `real_home` asserted absent at the end, exactly as in 1.8.

Recording stubs go in `$TMPDIR/rec`. Each appends `<name> <args>` to
`$TMPDIR/writes` and exits 0:
- `sudo`, `pkexec`, `nmcli`, `tee`, `usermod`, `gpasswd`, `systemctl`,
  `pacman`, `omarchy-pkg-drop`, `rm`;
- `timedatectl`, which records only when `$1` starts with `set-`; for
  `list-timezones` it prints `Europe/Oslo`.

Answer stubs go in a per-case dir:

| case | stubs |
|---|---|
| setup sudoless | `omarchy-sudo-docker` → exit 0 |
| remove sudoless | `omarchy-sudo-docker` → exit 1 |
| setup fingerprint | `omarchy-hw-fingerprint` → 0, and no `fprintd-enroll` on `PATH` |
| setup fingerprint, enabled | `omarchy-hw-fingerprint` → 0, and a `fprintd-enroll` stub on `PATH` |
| timezone | `omarchy-menu-select` prints `Europe/Oslo`, `omarchy-notification-send` appends its args to `$TMPDIR/notify` |
| all | `gum` → 0 |

`PATH` is `<case stubs>:$TMPDIR/rec:$bin:<nativeBuildInputs>`. `rm` is a
stub, so the harness's own clean-up uses `command -p rm` or the coreutils
store path.

Export `USER=tester`. Also stub `fprintd-verify` (exit 0), `omarchy-shell`
(exit 0) and `omarchy-state` (exit 0) in `$TMPDIR/rec`, without recording
them.

For each case, run `rc=0; bash "$bin/<script>" <args> >out 2>&1 </dev/null || rc=$?`.
Then check the rows **in this order**: writes first, so that a script which
reaches a writer stub, and then exits 0 because the stub succeeded, reports
the writer and not just its exit status. Collect the failures, print all of
them, and fail if any:

| must hold | otherwise fail with |
|---|---|
| `$TMPDIR/writes` is empty | `menu-guidance: <name> called <first line of writes>` |
| `out` (for timezone, `$TMPDIR/notify`) contains the case's marker | `menu-guidance: <name> did not name <marker>` |
| `rc` is 1 | `menu-guidance: <name> exited $rc` |

The cases, with the arguments each script gets and the marker it must name:

| script | args | marker |
|---|---|---|
| `omarchy-dns` | `Cloudflare` | `networking.nameservers` |
| `omarchy-dns` | `Custom` | `networking.nameservers` |
| `omarchy-setup-security-sudoless-docker` | — | `extraGroups` |
| `omarchy-remove-security-sudoless-docker` | — | `extraGroups` |
| `omarchy-remove-security-fingerprint` | — | `services.fprintd` |
| `omarchy-remove-security-fido2` | — | `security.pam.u2f` |
| `omarchy-setup-security-fingerprint` | — | `services.fprintd.enable` |

The "setup fingerprint, enabled" case asserts the opposite. The script must
get past the guard, so the first line of `writes` must be
`sudo fprintd-enroll <user>`, and `rc` is not checked. That is what shows
enrollment is reachable once fprintd is on. Otherwise it fails with
`menu-guidance: setup fingerprint never reaches fprintd-enroll with fprintd on`.
| `omarchy-menu-timezone` | — | `time.timeZone = "Europe/Oslo"` |

Clear `writes` between cases.

→ Verify: build `menu-guidance`. It must be green.

Traps: T-add, T-heredoc (printf only, `''${`), T-pipe, T-env, T-drv.

**2.6 Baseline commit, then the §1 proofs.**

1. In `default.nix`, comment out the `omarchy-dns` `substituteInPlace` only,
   and rebuild the `omarchy` package and `menu-guidance` (T-tier). Expected
   red: `menu-guidance: omarchy-dns called sudo -n -l -l /usr/bin/omarchy-dns Cloudflare`.
   That is `sudo_grants_passwordless`, `$T/bin/omarchy-dns:55-57`, which is
   the first thing `require_root` runs. The sudo stub prints nothing, so
   `grep '!authenticate'` fails and `exec pkexec` follows. The `did not name`
   and `exited 0` lines come after the first one.
2. The same for `omarchy-menu-timezone`. Expected red:
   `menu-guidance: omarchy-menu-timezone called sudo timedatectl set-timezone Europe/Oslo`,
   followed by `… did not name time.timeZone = "Europe/Oslo"` and
   `… exited 0`.
3. The same for `omarchy-remove-security-fido2`. `/etc/fido2` does not exist
   in the sandbox, so the script skips its `rm` and reaches the package
   drop. Expected red:
   `menu-guidance: omarchy-remove-security-fido2 called omarchy-pkg-drop libfido2 pam-u2f`.
4. Delete the whole `"remove.security.sshd" = { … };` override. Upstream's
   row returns, with `omarchy-remove-security-sshd`. Expected red:
   `menu-actions: remove.security.sshd reaches omarchy-remove-security-sshd: …, with no entry in data/menu-actions.nix`.
   The group list starts with `systemctl-system` and `ufw`; record it.

Restore each one with `git checkout HEAD --`, and see green. The red outputs
go in the PR.

Traps: T-break, T-tier, T-drv.

**2.7 PR**, as in 1.12. The subject is `DNS, sshd, sudoless Docker,
fingerprint, FIDO2 and timezone rows explain the declarative route instead
of writing state a rebuild undoes`. Use `Refs #1304`.

### Part 3: class 4, unsupported rows (branch `fix/1304-menu-unsupported-rows`, from `main` after Part 2 merges)

**3.1 Overrides.**
File: `modules/apps.nix`, in the `overrideSpec` literal:

```nix
        # #1304: hidden on NixOS; each needs something this port does not have.
        "install.windows".when = "false"; # rooted Docker and an FHS PATH
        "remove.windows".when = "false";
        "trigger.hardware.hybrid-gpu".when = "false"; # supergfxd, /usr/lib/systemd/system-sleep
        "setup.direct-boot".when = "false"; # efibootmgr and an Omarchy UKI
        "install.ai.hermes".when = "false"; # /usr/share/hermes-desktop
        "remove.ai.hermes".when = "false";
        "install.ai.perplexity".when = "false"; # a pacman package nixpkgs lacks
        "remove.ai.perplexity".when = "false";
        "remove.browser.brave-origin".when = "false"; # AUR-only
```

→ Verify: `nix fmt`, then rebuild the menu; all nine ids must show
`"when": "false"`.

Traps: T-fmt, and the "already defined" check from 2.3.

**3.2 `data/menu-actions.nix`.**
- **Each of the nine ids** gets exactly this reason. Any
  `pending #1304 class 4` entry becomes it.

  | id | reason |
  |---|---|
  | `install.windows`, `remove.windows` | `hidden: needs rooted Docker and an FHS PATH (decision 12)` |
  | `trigger.hardware.hybrid-gpu` | `hidden: needs supergfxd and /usr/lib/systemd/system-sleep (decision 12)` |
  | `setup.direct-boot` | `hidden: needs efibootmgr and an Omarchy UKI (decision 12)` |
  | `install.ai.hermes`, `remove.ai.hermes` | `hidden: needs /usr/share/hermes-desktop (decision 12)` |
  | `install.ai.perplexity`, `remove.ai.perplexity` | `hidden: a pacman package nixpkgs lacks (decision 12)` |
  | `remove.browser.brave-origin` | `hidden: AUR-only (decision 12)` |
- **`data/menu-exceptions.nix`:** `install.ai.hermes` gets the reason
  `hidden (#1304): upstream installs a binary with its own installer under
  /usr/share/hermes-desktop; nixpkgs has no hermes`. `install.ai.perplexity`
  gets `hidden (#1304): a pacman package nixpkgs does not carry, not a web
  app`. Both **stay** in the file (Summary, decision 15).

→ Verify: build `menu-actions`, which must be green. If the T-tier VM rule
allows, run `checks.options` as well; otherwise leave it to CI.

Traps: T-drv, T-tier.

**3.3 §1 proofs.**

1. Delete the `trigger.hardware.hybrid-gpu` line from 3.1 (its entry stays
   `hidden:`). Expected red:
   `menu-actions: trigger.hardware.hybrid-gpu is listed hidden but its when is 'omarchy-hw-hybrid-gpu'`.
2. Also delete its entry. Expected red:
   `menu-actions: trigger.hardware.hybrid-gpu reaches omarchy-toggle-hybrid-gpu: etc-write, systemctl-system, with no entry`.
   The group list may be longer; record it. These are executed lines,
   `$T/bin/omarchy-toggle-hybrid-gpu:39,73`.
3. Delete the `setup.direct-boot` line (its entry stays). Expected red:
   `… setup.direct-boot is listed hidden but its when is ''`.

Restore and see green. Paste all three.

Traps: T-break, T-drv.

**3.4 PR**, as in 1.12. The subject is `Menu rows that cannot work on NixOS
(Windows VM, hybrid GPU, direct boot, Hermes, Perplexity, Brave Origin
removal) are hidden`. Use `Refs #1304`.

### Part 4: class 3, existing routes (branch `fix/1304-menu-existing-routes`, from `main` after Part 3 merges)

**4.1 Overrides.**
File: `modules/apps.nix`, in the `overrideSpec` literal:

```nix
        # #1304: the routes nixarchy already has.
        "install.gaming.geforce-now" = {
          action = "nixarchy-service-enable geforce-now";
          description = "Flatpak — declared in your configuration, but updated by Flathub rather than by a rebuild";
        };
        "install.ai.ollama" = {
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-local-ai";
          description = "Ollama is programs.nixarchy.localAi here: set it up in a terminal";
        };
```

→ Verify: rebuild the menu. The build log must now print 15
`sibling rule:` lines, including
`remove.gaming.geforce-now -> nixarchy-service-disable geforce-now`.

Traps: T-fmt.

**4.2 Font terminal.**
File: `pkgs/omarchy/nix-bin/omarchy-install-font`. Insert between `:45`
(the `fi` closing the installed branch) and `:47`
(`echo "$name is not installed."`):

```bash
# A menu row runs this with no terminal, so the route below would print to
# nowhere; show it in one (#1304). The installed branch above stays silent.
if [[ ! -t 1 ]]; then
  exec omarchy-launch-floating-terminal-with-presentation \
    "omarchy-install-font $(printf '%q ' "$name" "$package" "$family")"
fi
```

Update its ledger row (`data/bin-ledger.nix:270-273`) reason to add
`; on the missing-font path with no terminal it reopens itself in one (#1304)`.

→ Verify: `bash -n`; build `checks.bin-ledger`.

Traps:
- T-tier: this rebuilds the omarchy package.
- `session.nix:1514` runs the installed path with a piped stdout, so it must
  still print `already installed`. The insert sits after that branch.

**4.3 Font check.** New `tests/install-font-terminal.nix`, registered in
`uniformChecks`. It is a `runCommand`, isolated as in 1.8. The stubs record
their args to `$TMPDIR/calls`: `omarchy-launch-floating-terminal-with-presentation`,
`omarchy-font-set` and `omarchy-pkg-add`.

- **Run 1:** `fc-list` prints nothing. Run
  `bash "$bin/omarchy-install-font" Iosevka ttf-iosevka-nerd 'Iosevka Nerd Font Mono' >out 2>&1`.
  The launcher must have been called, with an argument containing
  `omarchy-install-font Iosevka`. Otherwise fail with
  `the not-installed path wrote to a non-terminal stdout and launched no terminal`.
- **Run 2:** `fc-list` prints `Iosevka Nerd Font Mono`. `omarchy-font-set`
  must have been called and the launcher must not. Otherwise fail with
  `the installed path opened a terminal`.

→ Verify: build it. It must be green.

Traps: T-add, T-heredoc, T-env, T-drv.

**4.4 Records.**
- **`data/menu-exceptions.nix`.** Every row stays (Summary, decision 15).
  New reasons:
  - `install.ai.ollama` = `rewired (#1304) to setup.local-ai's action: Ollama is programs.nixarchy.localAi, a service rather than an app.`
    This replaces the line that names the non-existent
    `programs.nixarchy.services.local-ai`.
  - `install.gaming.geforce-now` = `rewired (#1304) to nixarchy-service-enable geforce-now, the Flatpak in data/flatpaks.nix.`
  - `install.gaming.xbox-cloud` = `a web app: omarchy-webapp-install, nothing to package.`
  - `install.gaming.battlenet` = `a Windows launcher under umu-launcher; the row ends at omarchy-pkg-add's declarative umu-launcher line.`
- **`data/menu-actions.nix`.** Rewrite or delete every `pending #1304
  class 3` entry, by the same rule as 2.4.
- **`tests/menu-actions.nix`.** Add `--no-pending` to the python call.

→ Verify: build `menu-actions`, which must be green. Run `checks.options`
under the T-tier rule, or leave it to CI.

Traps: T-drv, T-tier.

**4.5 §1 proofs.**

1. Delete 4.2's `if` block. Expected red:
   `the not-installed path wrote to a non-terminal stdout and launched no terminal`.
2. Remove `[[ ! -t 1 ]]` from the condition, so it reads `if true`, and move
   the block above the installed branch. Expected red:
   `the installed path opened a terminal`.
3. Add `"install.ai.ollama" = "pending #1304 class 3";` to the entries.
   Expected red: `menu-actions: pending reason left after the series: install.ai.ollama`.
   If the row is not flagged, it is
   `menu-actions: entry for install.ai.ollama, which reaches no hazard: stale`
   as well. Record both.

Restore and see green. Paste all three.

Traps: T-break, T-tier, T-drv.

**4.6 PR**, as in 1.12. The subject is `GeForce NOW, Ollama and missing-font
menu rows go straight to the route nixarchy already has`.

- The body says `closes #1304`. This is the last Part. Before writing it,
  check that Parts 1 to 3 merged:
  `gh pr list --search 1304 --state merged`.
- The body also lists the follow-ups for the owner, unfiled:
  - provisioning's `omarchy-refresh-applications` hazard;
  - the upstream questions on `remove-preinstalls`, the `elixir|phoenix`
    arm and Battle.net's confirm wording;
  - turning the class 4 rows into `disabled` + reason rows once #1301 has
    landed.

## Tests

Every check is built as `d=$(nix eval --raw .#checks.x86_64-linux.<n>.drvPath)`,
then `flock /mnt/data/vmtest/codex-build.lock nix build "$d^*" --print-build-logs`.

| check | Part | green means |
|---|---|---|
| `menu-actions` | 1 to 4 | ends `menu-actions: N rows with an action, F flagged, H hidden` |
| `remove-preinstalls` | 1 | no output after the build, exit 0 |
| `menu-guidance` | 2 | every case passes |
| `install-font-terminal` | 4 | both runs pass |
| `bin-ledger`, `patched-files`, `menu-verbs` | 1 to 4 | as on `main` |
| `options` (coverage.py), `session` | 1 to 4 | **VM tier**: only when no CI run is in flight, otherwise CI's. A failure in `session.nix:1514` (font) or `:1824` (`omarchy-dns` `/usr` exception) points at Parts 4 and 2 |
| `nix fmt -- --ci`, statix, deadnix | every Part | clean |

## Rollback

Each Part is one squashed commit on `main`. `git revert <sha>` undoes it on
its own, and it can be reverted in any order, with two exceptions:

- **Reverting Part 1 reverts `checks.menu-actions`.** Later Parts edit
  `data/menu-actions.nix`, so revert newest first.
- **Reverting the sibling rule (Part 1) also un-rewires
  `remove.gaming.geforce-now` (Part 4).** That is harmless: it returns to
  upstream's row.

Nothing touches state outside the repository. No migration, option or
user-file change ships, so a revert plus a rebuild restores the previous
menu exactly.
