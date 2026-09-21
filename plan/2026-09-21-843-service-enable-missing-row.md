---
status: approved
issue: 843
spec: spec/2026-09-21-843-service-enable-missing-row.md
---

# Plan: enabling a service works on an older services.nix

## Approved decisions (from the spec)

- `nixarchy-catalogue-diff` gains `--add-one <part> <id>`: it adds just
  `#@ <id>` from `<part>-template.nix` through the existing
  before-the-closing-brace path (with the `programs.nixarchy.apps.` rewrite
  for apps, and the usual dated heading), and honours `NIXARCHY_TEMPLATES`.
  - Marker already present: no change, exit 0.
  - Not in the template: "no <id> in <template>", exit 1.
  - No closing brace on its own line: today's refusal, exit 1.
  - A bad `<part>` or `<id>`: usage, exit 2.
- The per-part loop body becomes a function that `--add` and `--add-one`
  both call. Today's two modes don't change.
- `nixarchy-service-enable`:
  - `-h`/`--help`, checked before validation, prints
    `usage: nixarchy-service-enable <service-id>` and "  A row missing from
    services.nix is added from /etc/nixarchy/services-template.nix.", then
    exits 0;
  - a missing marker calls `nixarchy-catalogue-diff --add-one services
    "$id"`, says "added the <id> row from the template", and continues to
    enable. If that call fails, today's message and exit 1.
- A row the user deleted is re-added when they ask for it. It goes before
  the attrset's closing `}`.

## Steps

1. **Tests first** (`tests/options.nix`, after "a service can be enabled
   and disabled, byte for byte", `:4158`), all run as
   `NIXARCHY_TEMPLATES="$vm/etc/nixarchy" run …`:
   - copy the template to `$svcfile` and delete the `#@ $svcid` line;
     `nixarchy-service-enable "$svcid"` exits 0, and its output names the
     added row. The marker line is live and sits before the last `^}` line.
     `diff` against the template shows only that row moved and uncommented,
     plus the heading;
   - `nixarchy-service-enable --help` exits 0, with `usage:` and "missing"
     in the output;
   - `nixarchy-catalogue-diff --add-one services definitely-not-a-row` exits
     1 and leaves `cksum` unchanged; `--add-one bogus x` exits 2;
   - `--add-one services "$svcid"` on a file that already has the row: exit
     0, `cksum` unchanged.

   → Verify: `nix build .#checks.x86_64-linux.options -L` fails at the
   first new assertion.
2. **`modules/apps.nix`, `nixarchy-catalogue-diff` (`:1153`)**: argument
   parsing for `--add-one`; the loop body is factored into
   `one_part <part> <marker-filter>`; `--add-one` calls it for one part with
   the one marker and its exit codes. → Verify with step 1's catalogue-diff
   assertions, and the existing "catalogue-diff finds a missing row and
   --add restores it" test still passing.
3. **`modules/apps.nix`, `nixarchy-service-enable` (`:1260`)**: the `--help`
   case before validation; the missing-marker branch calls
   `nixarchy-catalogue-diff --add-one services "$id"`. → Verify that step
   1's service-enable assertions pass, and so does the existing
   enable/disable test.
4. **Docs**: wherever the manual mentions `nixarchy-catalogue-diff` or
   `nixarchy-service-enable`, add `--add-one` and the self-healing
   behaviour (`git grep -n` both names in `docs/`), keeping to that page's
   register. → Verify by reading the changed paragraphs.
5. **Check and ship**: the `options` check, the repo's `lint` and `apps`
   checks, then a PR with "Closes #843" linking intent, spec and plan.
   → Verify that CI is green.
6. **After merge and a nixarchy bump on razer:**
   `nixarchy-service-enable --help` prints the usage, and the
   nixarchy-microvm form no longer warns on razer's `services.nix`, which
   lacks the row (the plugin detects #843). → Verify with a still of the
   form flipped to permanent.

## Tests

`nix build .#checks.x86_64-linux.options -L` · the existing catalogue-diff
and enable/disable tests unchanged · CI · step 6 on razer.

## Rollback

Revert the PR. `--add-one` and the self-healing go away, and
nixarchy-microvm's up-front warning returns on its own, since it only
stops when `--help` says so.
