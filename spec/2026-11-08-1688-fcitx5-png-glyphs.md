---
status: approved
issue: 1688
intent: intent/2026-11-08-1688-fcitx5-png-glyphs.md
---

# Spec: the Fcitx candidate window has its arrows on NixOS 26.05 too

## Design

### 1. The script (intent decision 1)

Upstream's `bin/omarchy-theme-set-fcitx5` links the packaged glyphs at its
lines 77-79:

```bash
for glyph in "$PACKAGED_THEME"/*.svg; do
  [[ -e $glyph ]] && ln -sfn "$glyph" "$THEME_DIR/${glyph##*/}"
done
```

It copies `theme.conf` from `$THEME_SOURCE` just before that (lines 68-73).
The template names `prev.svg`, `next.svg`, `radio.svg` and `arrow.svg`
(`default/themed/fcitx5-theme.conf.tpl:48,57,87,90`).

The change, after the copy and in place of that loop:

- link every `"$PACKAGED_THEME"/*.svg` and `*.png`, whichever exist;
- for each `Image=<name>.svg` in the copied `theme.conf` whose SVG is not
  in `$PACKAGED_THEME` but whose `<name>.png` is, rewrite that line to
  `Image=<name>.png` (`sed -i` on the copy, never on `$THEME_SOURCE`).

On unstable (fcitx5 5.1.23, SVG) both steps are no-ops beside today. On
26.05 (5.1.19, PNG) the theme names the files that exist.

**A carried patch, not `substituteInPlace`.** The change replaces a
three-line loop with about eight lines. `--replace-fail` on a multi-line
block is brittle to read and review, while a `--fuzz=0` patch fails the
build on any upstream rewording, which is what's wanted. It is
`pkgs/omarchy/1688-fcitx5-png-glyphs.patch`, applied next to the existing
`substituteInPlace` for this script (`pkgs/omarchy/default.nix:883-885`),
after that path substitution, with a `# Why: pkgs/AGENTS.md#...` pointer
and a short CARRIED section in `pkgs/AGENTS.md`. It is NixOS-specific
(Arch's fcitx5 always ships SVG), so the section says it is not meant
upstream.

### 2. Existing machines

A script fix reaches a theme directory only when the script next runs.
That is a theme change or activation, never an upgrade, which #1624 already
recorded (`intent/2026-11-05-1624-fcitx5-theme.md:41-43`). A 26.05 user who
never changes theme would keep the missing arrows. So a post-boot hook,
`omarchy/hooks/post-boot.d/fcitx5-glyphs` in `modules/home.nix` beside
`user-migrations` (`:2458`), runs `omarchy-theme-set-fcitx5` (no
`--activate`, so the user's classicui choice is untouched) when
`~/.local/share/fcitx5/themes/omarchy/theme.conf` exists and any of its
`Image=` values names a file missing from that directory. Otherwise it
does nothing. It is idempotent: once the images resolve, it never runs the
script again.

**Timing limit:** the hook runs at login (`post-boot.d`). A machine upgraded
mid-session gets its arrows at the next login, not at the switch. The
candidate window works without them meanwhile, only without its page and
menu arrows. It sits under the same `enable` as the user-migrations hook,
so Mode A is untouched.

### 3. The probes (§1 read backwards)

Two checks, two properties:

- `tests/session.nix:3410-3414` (the **generated** theme) deletes `prev.svg`, reruns
  `--activate`, and tests `prev.svg`. It becomes: delete every glyph link
  in the theme directory, rerun `--activate`, then for every `Image=` value
  in `~/.local/share/fcitx5/themes/omarchy/theme.conf`, `test -e` it in that
  directory (`-e` follows the link, so a dangling one fails), and assert at
  least one `Image=` line exists. This runs in both `checks.session`
  (unstable) and the weekly `stable-session` (`weekly.yml:90`, the same
  check against nixos-26.05), so one assertion covers both channels.
- `tests/input-methods.nix:342` (the **packaged** theme directory) tests
  `${linked}/share/fcitx5/themes/default/prev.svg`. It becomes: each of
  `prev`, `next`, `radio` and `arrow` exists as `.svg` or `.png`. The
  property it guards is "the packaged glyphs are linked", not their format.
- The repair hook, from a pre-fix state on each channel: `checks.session`
  (unstable) and `stable-session` (26.05) both write a theme directory as a
  26.05 machine has it before this fix: a `theme.conf` copied from the
  template, whose `Image=` lines still name `.svg`, and no glyph links. Then
  they run the hook and assert every `Image=` resolves. On 26.05 that needs
  the rewrite to `.png`; on unstable it needs the links. A second run must
  not touch the directory (mtime unchanged).

## Alternatives rejected

- **Always use unstable's fcitx5 SVGs** (a separate fcitx5 for the glyphs).
  That ships a second fcitx5 data set on stable, which drifts from the
  running daemon.
- **Rename PNGs to `.svg`.** classicui loads by content type, and a PNG
  named `.svg` is a broken image rather than a missing one.
- **Fix only the tests.** That hides the user-visible bug.

## Risks

- A user who customised `theme.conf` by editing the copy loses the
  rewrite on the next sync. That is no change: the script already
  overwrites the copy from `$THEME_SOURCE` on every run.
- A future fcitx5 that ships both formats gets the SVG, as today.
- No effect off the input-methods path: the script runs only from theme
  sync and activation.

## Verification

- `checks.input-methods` (cheap): passes. Built with the `.png`-or-`.svg`
  edit reverted to `.svg` only, it still passes on unstable, which is
  expected. Its job is "linked", not "format".
- `checks.session` (VM tier): the new `Image=` loop passes. §1 break, the
  same on both channels: the script reads `OMARCHY_FCITX5_PACKAGED_THEME`
  before its default (upstream line 12). The probe points it at a fixture
  directory holding only `prev.png`, `next.png`, `radio.png` and `arrow.png`,
  which is the 26.05 layout, made on any channel. With the patch, the theme
  resolves (PNG links, `Image=` rewritten). With the patch line removed from
  `default.nix`, nothing is linked and `Image=prev.svg` fails "names a file
  that does not exist". The patched run passes and the reverted run fails,
  whichever channel builds it.
- The weekly `stable-session`, dispatched once on the branch
  (`gh workflow run weekly.yml -f job=stable-session --ref <branch>`), is
  the 26.05 proof. It failed at `tests/session.nix:3413` before (run
  42466135557) and must pass after.
- `checks.omarchy` (package tier) for the patch applying, plus
  `checks.patched-files`, fmt, statix, deadnix and `grep-q-pipefail`.

## Decisions (owner, 2026-11-08, on the draft)

1. The post-boot repair hook stays as designed: it reruns the sync once, only when `theme.conf` names a missing image.
