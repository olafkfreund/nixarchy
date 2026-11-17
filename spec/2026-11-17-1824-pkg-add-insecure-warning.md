---
status: draft
issue: 1824
intent: intent/2026-11-17-1824-pkg-add-insecure-warning.md
---

# Spec: `nixarchy-pkg-add` warns after adding an insecure package

All code is in `nixarchy-pkg-add` (`modules/apps.nix`); the test is in
`tests/pkg-index.nix`. Anchors by name; lines move.

## Design

1. In the probe expression (`nix-instantiate --eval --strict --json --expr "
   { attrsJson }: ..."`, attribute set `v`), add an `insecure` boolean beside
   `broken`, with the index's definition (`row` in `modules/pkg-index.nix`),
   each predicate guarded on its own so the existing outer `tryEval` around
   `deepSeq v v` never sees a throw from it:
   In `probe`'s `let`, beside `ls` (NOT inside the `v = { ... }` set):
   ```
   try = x: d: let r = builtins.tryEval x; in if r.success then r.value else d;
   m = try (q.meta or { }) { };
   ```
   and in `v`, beside `broken`:
   ```
   insecure = builtins.isAttrs m && (
     try ((m.insecure or false) == true) false
     || try (let kv = m.knownVulnerabilities or null;
             in builtins.isList kv && kv != [ ]) false);
   ```
   (`try`'s local `r` shadows `probe`'s `r` harmlessly.) Only a boolean
   enters `v`, so `deepSeq` cannot force the list's elements. The probe sits in
   a bash double-quoted string inside a Nix `''` string: the new text contains
   no `$`, backtick, backslash-quote beyond the existing `\"` convention, and
   no `''`.
2. In the flags paragraph after the broken test, add
   `if [ "$(jq -r .insecure <<<"$info")" = true ]; then flags="$flags [insecure in nixpkgs -- the rebuild will refuse it unless you permit it]"; fi`.
   Order is unfree, broken, insecure. The package is still added.
3. A package that failed to resolve (`ok:false`) never reaches the paragraph;
   `.insecure` is absent only there. The other-channel branch `continue`s
   before the flags paragraph and is untouched (no notice, like unfree and
   broken).
4. Wording follows the picker's `Marked INSECURE in nixpkgs.` and the broken
   notice's shape; "unless you permit it" because the refusal is nixpkgs'
   own (`permittedInsecurePackages`, `allowInsecurePredicate`), which
   `nixarchy-pkg-add` cannot answer for.

## Alternatives rejected

- Importing one shared definition into the index and the probe: the index is
  run from a lone store copy of `modules/pkg-index.nix` (`walk=${./pkg-index.nix}`),
  so a relative import of a sibling file would not resolve; passing the path
  as an argument widens the index's interface for one boolean. A cross-check
  test (below) holds the two together instead.
- Refusing the add, or prompting: the issue asks for a warning "as it does for
  unfree and broken"; a refusal would also stop a user who has already
  permitted the package.
- Adding the notice to the other-channel row: that row says it brings its own
  closure and has never carried unfree/broken notices; out of scope.
- Reading `meta.insecure` bare, like `broken`: a throwing field would make a
  resolvable package report "no match" and skip the add.

## Risks

- A shell-in-Nix quoting slip in the probe makes every `nixarchy-pkg-add`
  evaluation fail, not only insecure ones: the whole check suite that adds a
  package (`app-selection`, `home-selection`, `pkg-index`) exercises the probe,
  which is the guard.
- `try` shadows nothing: it is local to the `--expr`.
- The notice only reflects `meta`; a package that nixpkgs refuses for another
  reason (`allowBroken`, unsupported system) is not claimed.
- Coexistence (CLAUDE.md s14): no merged env or option touched; none.

## Verification

In `tests/pkg-index.nix` (cheap tier), with the same fixture nixpkgs as the
index (one definition of the fixtures):

- Setup. Copy `nixarchy-pkg-add` from `testLib.vmPackage "nixarchy-pkg-add"`
  to a writable file and `sed` its baked `nixpkgs=` line to the fixture path;
  assert with `grep -qF "nixpkgs=${fixture}"` that the rewrite landed (an
  unrewritten script would silently run the real nixpkgs). No `--home`: the
  system-scope file is `$XDG_CONFIG_HOME/nixarchy/apps.nix`, as in
  `tests/app-selection.nix`. Private `HOME`, `XDG_CONFIG_HOME`,
  `XDG_STATE_HOME`, `NIX_STATE_DIR`, `NIX_LOG_DIR`. Before every run, rewrite
  that file to the empty marker block (`{ pkgs, ... }:` / `{` /
  `  environment.systemPackages = with pkgs; [  #@pkgs-begin` /
  `  ];  #@pkgs-end` / `}`), because a second add of the same name reports
  "already in". Each run is a plain command with its rc captured (`|| rc=$?`),
  since the check runs under `set -eo pipefail` and `fixThrowMeta` exits
  non-zero with "no match".
- Attributes: every `.attr` in `walk.json` except `fixCurated` (it redirects to
  an app through the VM's baked curated table, which is not the fixture's).
  That includes `sub.child` and `fixNoVersion` (the probe never reads
  `version`; `fixNoVersion` has a `name`). `fixThrowMeta` is expected to
  report "no match" and rc != 0, as today; assert exactly that.

Cases:

1. Drift check: write the attrs whose report row contains `[insecure in
   nixpkgs` to a file, write the index's `insecure == true` attrs from
   `walk.json` minus `fixCurated` to another, assert the first is non-empty
   and the two are equal (files compared with `diff`, never process
   substitution, so a failing producer is not swallowed).
2. `fixAll` carries `[unfree`, then `[broken`, then `[insecure` in that order
   on its row. `fixClean`'s row ends exactly in `fixClean-1.0 -- clean package`
   (no bracket anywhere). No self-comparison against a mutated copy of the
   script.
3. `fixThrowVuln`, `fixThrowElem`, `fixThrowInsecureList`, `fixInsecureThrowVuln`
   all report `added`, rc 0 (never "no match"); of these, `fixThrowVuln` and
   `fixThrowElem` and `fixThrowInsecureList` must NOT carry the notice except
   `fixThrowInsecureList`/`fixInsecureThrowVuln`, which the index also marks
   (their expected value is whatever case 1's walk set says).
4. Break proofs (CLAUDE.md s1), each shown landed by `git diff`, output in the PR:
   (i) delete the flags-paragraph line: case 1 fails. (ii) read
   `q.meta.insecure or false` bare in the probe: case 3 fails on
   `fixThrowInsecureList`. (iii) remove the `try` around the
   `knownVulnerabilities` read: case 3 fails on `fixThrowVuln`.
5. Build `app-selection`, `home-selection`, `pkg-index`, `pkg-new`, statix,
   deadnix, `nix fmt`, and the final full generated set once, with the
   options shards if the gates allow.
