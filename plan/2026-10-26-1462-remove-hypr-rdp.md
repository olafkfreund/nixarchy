---
status: draft
issue: 1462
spec: spec/2026-10-26-1462-remove-hypr-rdp.md
---

# Plan: remove hypr-rdp

This plan stands alone. Line numbers are against `origin/main` at 27a36bff,
as read by a read-only review. Re-check each before editing. Never edit
`intent/`, `spec/` or `plan/` files other than this one: they are history.

## Decisions carried from the spec

1. **The 10 options under `programs.nixarchy.services.hypr-rdp`** (defined at
   `modules/services/hypr-rdp.nix:158-277`) are replaced by one
   `mkRemovedOptionModule`, at `modules/services/default.nix:77`, with the
   text in the spec.
2. **Hidden options are skipped** by `tests/doc-options.nix` and by
   `.github/scripts/release-notes-options.nix`.
3. **`tests/hypr-rdp-builds.nix` becomes `tests/sops-evaluates.nix`**, a
   reference configuration plus one sops secret, forcing `setupSecrets`.
4. **`nixarchy-remote` goes; freerdp stays,** with its note rewritten.
5. **No manual page is deleted.** The RDP sections of `remote-desktop.md` are.

## Steps

1. **Module and removal message.**
   - a. Delete `modules/services/hypr-rdp.nix`. In
     `modules/services/default.nix`, replace the `(import ./hypr-rdp.nix
     inputs)` import (line 77) with the spec's `mkRemovedOptionModule` line.
     Both `inputs` and `stableInputs` contain `nixpkgs` (`flake.nix:505-510`).
     Rewrite the header (39-72) so it no longer uses hypr-rdp as the example;
     microvm is now the only module that takes `inputs`.
     **Trap:** keep the explanation that nixarchy never sets
     `nixpkgs.overlays`, which `modules/home.nix:98-101` points at.
   - b. In `tests/doc-options.nix`, change the `lib.isOption value` branch to
     `lib.optional ((value.visible or true) != false) { option = path; }`.
   - c. In `.github/scripts/release-notes-options.nix`, inside
     `if isOpt v then`, return `{ }` when `(v.visible or true) == false`.
   - d. In `modules/services/microvm.nix:76-81`, drop the two hypr-rdp
     comparisons from the description.
   - **Trap:** `pkgs/secret.nix:153` walks `programs.nixarchy.services`;
     `tryV` must catch the removal throw. Build `checks.secret-new` to prove
     it.
2. **`data/services.nix:73-78`:** delete the `hypr-rdp` entry.
   `tests/options.nix:3365` requires each bundled entry to have a module, so
   the entry goes in the same commit as the module.
3. **Flake.**
   - Delete:
     - the input at `flake.nix:126-130`;
     - the overlay entry at 798-807;
     - the comment and `packages.hypr-rdp` at 1096-1105;
     - the check entries at 1838-1849;
     - the `remote-tunnel` entry at 2319-2328.
   - Add `"sops-evaluates"` to `uniformChecks`.
   - Reword the comment at 1069 to "where zen-browser went".
   - Delete `pkgs/hypr-rdp/`.
   - Run `nix flake lock`, never `update`. The diff should drop only the
     `hypr-rdp` node and its root entry (`flake.lock:287-306,1301`).
4. **`nixarchy-remote`.**
   - Delete `pkgs/omarchy/nix-bin/nixarchy-remote` and its row at
     `data/bin-ledger.nix:98-102`, in the same commit (`checks.bin-ledger`
     checks both directions).
   - In `pkgs/omarchy/default.nix`, delete the `setup.remote.serve` and
     `setup.remote.connect` rows (182-183), drop `"rdp"` from the
     `setup.remote` aliases (181), and trim the comment at 159-178 to the gliff
     rows.
   - In `modules/apps.nix:3673`, replace the line with:
     `remote) echo "nixarchy remote is retired (#1462) -- use gliff: Setup > Remote desktop > Connect with gliff." >&2; exit 1 ;;`
   - In `data/apps.nix:545-574`, keep freerdp and rewrite its comment and
     note. The note points at "Connect to a machine", which is gone.
   - **Trap:** run `grep -rn nixarchy-remote tests/demo/` (AGENTS.md §4).
5. **CI.**
   - `.github/scripts/cache-allowlist.sh:42-48`: delete the comment and
     `echo ".#hypr-rdp"`.
   - `build.yml:1459-1469`: rename the step to "Build the box image before
     publishing", make it `nix build --no-link .#box-test-image`, and trim its
     comment.
   - `build.yml:1605-1610`: delete the "Build hypr-rdp, which checks.options
     needs" step.
   - `build.yml:1360-1363`: reword the comment that splits by what builds
     hypr-rdp.
   - `docs/internals/workflows.md:110-112`: drop the hypr-rdp sentence.
6. **Tests.**
   - **`tests/sops-evaluates.nix`:** `git mv tests/hypr-rdp-builds.nix
     tests/sops-evaluates.nix` and replace its content with:
     ```nix
     { inputs, pkgs }:
     # A host that declares a sops secret can be DESCRIBED: setupSecrets evaluates,
     # which forces sops-nix's sops-install-secrets (#1030). checks.options never
     # forces the closure. hypr-rdp, removed in #1462, was the feature that met
     # this; sops-nix stays, so the probe does too (data/pin-fix.nix, #1459). An
     # integer, not a drvPath: see tests/AGENTS.md on drvPaths as build inputs.
     let
       withSecret = inputs.self.nixosConfigurations.reference.extendModules {
         modules = [
           {
             sops = {
               validateSopsFiles = false;
               age.keyFile = "/var/lib/sops-nix/key.txt";
               defaultSopsFile = ../flake.nix;
               secrets.probe = { };
             };
           }
         ];
       };
     in
     pkgs.runCommand "nixarchy-sops-evaluates"
       { proof = builtins.stringLength withSecret.config.system.activationScripts.setupSecrets.text; }
       ''
         if [ "''${proof:-0}" -lt 32 ]; then
           echo "FAIL: setupSecrets is $proof characters; this no longer forces sops-install-secrets."
           exit 1
         fi
         echo "a host with a sops secret evaluates: setupSecrets is $proof characters"
         touch $out
       ''
     ```
     Then delete `tests/hypr-rdp-toml.nix`, `tests/rdp-docs.sh` and
     `tests/remote-tunnel.nix`.
   - **`tests/options.nix`:**
     - delete the RDP cases (1973-2001);
     - delete the RDP fixtures (2758-2814) and `rdpUnitOf` (2820), keeping
       `failedAssertions` and `mentions` (2816-2818);
     - delete the `rdp*` environment variables (3492-3500);
     - delete the script block from "hypr-rdp refuses, at both layers"
       through "the RDP unit refuses missing or empty passwords" (3708-3819);
     - reword the sops comment (2724-2727);
     - add:
       ```nix
       hyprRdpRemoved = {
         on = mentions "no longer has any effect" (failedAssertions (configBeside { programs.nixarchy.services.hypr-rdp.enable = true; }));
         off = mentions "no longer has any effect" (failedAssertions defaultMachine);
       };
       ```
       If the removal surfaces as an evaluation `throw` rather than a failed
       assertion, retarget the case to catch the throw (`builtins.tryEval`
       catches `throw`), and record the change here.
   - **`tests/session.nix`:**
     - delete `rdpFixture` (112-130), `services.hypr-rdp` (171-175), the
       `sops` block (179-187), and `sessionAgeKey` with
       `setupSecrets.deps` (268-271);
     - in the probe (707-735), keep only `def on_desktop` (716-719).
     - **Trap:** `on_desktop` is used about 20 more times below.
   - **`tests/menu-verbs.nix`:** delete lines 128, 137, 168-172 and 245-248.
   - **`tests/menu-tree.py`:** in `EXPECTED`, change `"connect"` to
     `"setup.remote.gliff"` and delete `"rdp"`.
   - **The other tests:**
     - in `tests/secret-enroll.nix` and `tests/config-repo-ownership.nix`,
       rename `hypr-rdp-password` to `example-password`;
     - in `tests/install-matrix.py:199-222`, keep only the gliff paragraph;
     - leave `tests/release-notes.nix:36,153` (a made-up fixture) and
       `tests/failure-digest/b-proofs.log:41` (a captured log).
7. **`tests/AGENTS.md`.**
   - 180-181: change the example to `nixarchy-secret`.
   - 185-238: keep the rule, and retarget the check name to
     `checks.sops-evaluates`.
   - 243-293: keep the general lesson; replace the hypr-rdp specifics with
     "removed in #1462".
   - 295-345: delete the RDP coverage list; keep the gliff paragraph and the
     `secret-enroll` bullet under a gliff heading.
8. **Docs.**
   - **`docs/manual/remote-desktop.md`:**
     - rewrite the intro (7-13) as gliff only;
     - delete 112-435, from "From Windows, macOS or a phone: RDP" up to
       "Letting an agent drive another machine";
     - reword "Not through RDP" and "the same key the Connect row tunnels
       with" in 436-507.
   - **Other manual pages:**
     - delete `docs/manual/configuration.md:533`;
     - rewrite or delete `docs/manual/security.md:71-75`;
     - in `docs/manual/secrets.md`, rename the example secret (81-134), drop
       the nixarchy-service example while keeping `passwordFile`, and reword
       255.
   - **Top-level docs:**
     - `README.md:55` and `:522`: drop the hypr-rdp clauses;
     - `docs/llms.txt:89` and `:137`: drop the RDP clauses.
   - **`docs/internals/flake.md`:**
     - delete 283-336 and 1083-1121;
     - reword 359 and 1537;
     - keep the anchor `declarative-secrets-adopted-for-one-concrete-reaso`
       (383), and add one line saying hypr-rdp was removed in #1462 and
       sops-nix stays.
   - **`modules/secrets.md`:** add a removal note, and put the claims at
     101-112 and 145 in the past tense.
   - **`pkgs/secret.nix`:** comments only (1-2, 8-10, 104).
9. **#1459:** not merged yet, so leave it. When it rebases, its
   `data/pin-fix.nix` sops-nix probe becomes
   `checks.x86_64-linux.sops-evaluates`.
10. **Final commit subject**, which becomes the release note: "hypr-rdp is
    removed; gliff, installed by default, is the remote desktop, and sops-nix
    stays".

## Tests

```sh
grep -rnI 'hypr-rdp\|hyprRdp\|hypr_rdp\|nixarchy-remote' --exclude-dir={intent,spec,plan,.git} . \
  | grep -v 'flake.lock\|failure-digest/b-proofs.log\|tests/release-notes.nix\|hyprRdpRemoved\|mkRemovedOptionModule\|modules/secrets.md\|docs/internals/flake.md'
nix build --no-link .#checks.x86_64-linux.{sops-evaluates,doc-options,docs-lists,bin-ledger,menu-verbs,test-registration,release-notes,secret-new,secret-enroll,config-repo-ownership,cache-budget,cache-entries} .#omarchy
.github/scripts/readme-counts.sh --check
.github/scripts/generated-checks.sh generated | grep -c 'hypr-rdp\|remote-tunnel'   # 0
```

**`checks.options` (11.5 GB):** only with CI idle (§6), otherwise left to CI.

**§1 proofs:**

- `sops-evaluates` red with
  `--override-input sops-nix github:Mic92/sops-nix/a8627b21` (the full rev
  if the short one fails);
- `hyprRdpRemoved` red without the removal line;
- `doc-options` red on a planted `programs.nixarchy.services.hypr-rdp.enable`
  mention.

## Rollback

Revert the squash commit. That brings the module, input and checks back.

## Who does what

The `coder` agent does steps 1-8, one agent, with later steps sent with
SendMessage. The session commits, runs the §1 proofs and opens the PR. The
review is a fresh Opus agent given this plan and the diff.
