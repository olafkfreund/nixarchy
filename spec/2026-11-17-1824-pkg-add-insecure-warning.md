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
   ```
   try = x: d: let r = builtins.tryEval x; in if r.success then r.value else d;
   m = try (q.meta or { }) { };
   insecure = builtins.isAttrs m && (
     try ((m.insecure or false) == true) false
     || try (let kv = m.knownVulnerabilities or null;
             in builtins.isList kv && kv != [ ]) false);
   ```
   `try` and `m` are new `let` bindings in `probe`, beside `ls`. Only a boolean
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
index: bake a copy of the `nixarchy-pkg-add` script whose `nixpkgs=` line
points at the fixture (the test already greps baked lines out of
`nixarchy-search`; same technique), run it against a throwaway
`~/.config/nixarchy/apps.nix` (the `#@pkgs-begin`/`#@pkgs-end` block from
`tests/home-selection.nix`'s `reset_files`) with
`NIX_STATE_DIR`/`HOME`/`XDG_*` private, adding every fixture attribute that
the index lists, one run each (`fixCurated` redirects to an app and
`sub.child` needs the dotted path: include `sub.child`, skip `fixCurated`;
`fixThrowMeta` reports "no match", as today).

1. The set of attributes whose report row carries `[insecure in nixpkgs` equals
   the index's `insecure == true` set from `walk.json` minus `fixCurated` and
   `fixNoVersion` if the add path cannot add it (decide by running; any other
   difference is a failure). This is the drift check against the picker.
2. `fixAll` carries `[unfree` then `[broken` then `[insecure` in that order;
   `fixClean` carries none and its row is byte-identical to what the unmodified
   script prints (compare to a row produced by the pre-change script text
   with the probe line removed, or assert the exact current row).
3. Throwing fixtures (`fixThrowVuln`, `fixThrowElem`, `fixInsecureThrowVuln`,
   `fixThrowInsecureList`) are added (rc 0, `added`), never "no match".
4. Break proof (CLAUDE.md s1): delete the flags-paragraph line, run, watch
   case 1 fail; read `meta.insecure` bare in the probe, watch case 3 fail.
   Output in the PR.
5. Build `app-selection`, `home-selection`, `pkg-index`, `pkg-new`, statix,
   deadnix, `nix fmt`, and the final full generated set once, with the
   options shards if the gates allow.
