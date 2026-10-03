---
status: approved
issue: 1179
spec: spec/2026-10-03-1179-seed-instrumentation-depth.md
---

# Plan: the install checks seed the installed system at the same import depths the VM uses

## Approved decisions (self-contained)

- **The real installed host's depths,** counted from the `nixosSystem`
  `modules` list (0):
  - depth 0: nixarchy, home-manager, disko, `hosts/<name>`;
  - depth 1: `default.nix` imports `host.nix`, `disk-config.nix`,
    `nixarchy-hardware.nix` and `configuration.nix`, and `configuration.nix`
    holds the configuration values;
  - depth 2: `configuration.nix` imports `hardware-configuration.nix`, which
    carries `install.sh`'s initrd pin, `nixarchy-apps.nix`, and in tests
    `test-instrumentation.nix`.
- **The seeds today** put `hardwareConfig`, `initrdPin` and `instrumentation`
  at depth 0. They move to depth 2.
- **One helper, `tests/lib/installed-target.nix`,** replaces the three tests'
  copies of:
  - `instrumentation`, `hardwareConfig`, `initrdPin` and `targetSystemFor`;
  - the `/etc/nixarchy/test-instrumentation.nix` text;
  - the cp/sed test-script lines.

  Its parameters: `{ inputs, pkgs }`, then `diskConfig`, `reference` (the
  config whose initrd lists are pinned), and `extraInstrumentation`
  (`install-encrypted`'s `console=ttyS0` and plymouth off). Hostname
  `installed` and username `omarchy` are unchanged.
- **New `checks.install-seed-shape` (evaluation only, cheap).** For the three
  tests' parameters, instrumented and not (six cases), it compares
  `system-path` `drvPath`:
  - **seed:** the helper's;
  - **VM:** a `nixosSystem` over `installer/template/flake.nix`'s module
    list, plus a host directory rendered from `installer/template/host/`.

  The directory is rendered by `install.sh`'s own `substitute_host_files`
  and `subst`, **extracted with `sed -n "/^fn()/,/^}/p"`**, the repo's
  pattern (`tests/installer-offline-rescue.nix:37`); sourcing `install.sh`
  starts the wizard. Then the helper's instrumentation edit is applied, and
  the directory is imported (IFD). It fails naming the case and both paths.
- **`nixarchy-hardware.nix` stays out of the seed** unless the check shows a
  difference; record which.
- **One paragraph in `tests/AGENTS.md`** on why the seed mirrors the
  template's depths (#1176, this check).

## Repo traps

- **Work only in `/mnt/data/vmtest/wt-1179`.** Scratch trees are
  `git worktree add --detach`, never `cp -a`.
- **New files are invisible to the flake until `git add`** (§5).
- **No heredoc inside a Nix `''` string** (§5); use `printf '%s\n'`. No
  `grep -q` in a pipe (`checks.grep-q-pipefail`). Capture status with
  `if …; then`.
- **After every `.nix` edit:** `nix fmt`, then `git diff --stat` (the
  nixpkgs-fmt hook trap); statix per file, deadnix.
- **Build tiers (§6):** evaluation and the new check are cheap (under
  `flock /mnt/data/vmtest/codex-build.lock`). **`install`, `free-space` and
  `install-encrypted` are VM checks: never build them locally;** CI and the
  nightly run them. Local proof is `drvPath` evaluation only.
- **§1:** commit a baseline before each break; restore with
  `git checkout HEAD -- <path>`; `grep` that the break landed.
- **The test scripts must keep doing exactly what they do now** (the same
  cp/sed, the same checks), only from the helper's single definition. Diff
  each `testScript` before and after.

## Steps

1. **The helper: `tests/lib/installed-target.nix` (new).**
   - Move `hardwareConfig`, `initrdPin` and `instrumentation`, **with their
     comments**, from `tests/install.nix:85-165` into it.
   - `targetSystemFor { cpuModule, instrumented ? false }` builds:
     ```nix
     modules = [ nixosModules.nixarchy  home-manager  disko
       { imports = [ host.nix  (disk-config.nix diskConfig)
           { imports = [ (hardwareConfig cpuModule) initrdPin ]
                       ++ optional instrumented (instrumentation // extraInstrumentation);
             <the configuration values, as in tests/install.nix:204-225> } ]; } ];
     ```
     Merge `extraInstrumentation` as a second import beside `instrumentation`,
     not with `//`.
   - Move the "The shape is load-bearing" comment here, extended with one
     line on depth 2 and #1176.
   - Return:
     - `targetSystemFor`;
     - `etcInstrumentation` (the `environment.etc."nixarchy/test-instrumentation.nix".text`
       module);
     - `instrumentScript`, the exact cp/sed/grep lines as one string.
   - **Verify:** it evaluates (`nix eval` of one `targetSystemFor` toplevel
     `drvPath`).

2. **Port `tests/install.nix`.**
   - Replace its local definitions and its `etc` text with the helper's.
     Interpolate `instrumentScript` where `:698-706` stands.
   - **Verify:**
     - the `drvPath` of `checks.install` evaluates;
     - diff the rendered `testScript` before and after: only whitespace or
       the interpolation should differ.

3. **Port `tests/free-space.nix`,** the same way (`diskConfig` with
   `mode = "free"`, `reference-unencrypted`). Verify as in step 2.

4. **Port `tests/install-encrypted.nix`.**
   - Its encrypted `reference` and `diskConfig`.
   - `extraInstrumentation` = its `console=ttyS0` and plymouth-off module
     (`:100-113`), comment kept.

   Verify as in step 2.

5. **The check: `tests/install-seed-shape.nix` (new), plus a `flake.nix`
   checks entry.**
   - **A `runCommand` renders a host dir per case:**
     - copy `installer/template/host/` to `hosts/installed/`, and
       `installer/disk-config.nix` to where `../../disk-config.nix` resolves;
     - write `hardware-configuration.nix` as the helper's `hardwareConfig`
       would read, plus the initrd pin. Simplest: a file that imports the
       helper's modules by store path;
     - write `nixarchy-hardware.nix` as `{ ... }: { }` unless step 6 shows
       otherwise;
     - set the shell variables (`hostname`, `username`, `device`,
       `disk_mode`, `timezone=UTC`, `keymap=us`, `encrypt`,
       `recovery_hash=`), and run the extracted `substitute_host_files`;
     - for instrumented cases, apply the helper's `instrumentScript` edit,
       paths adjusted.
   - **Evaluation:** import that dir as the template's `hosts/<name>` module
     inside `nixosSystem` with the template's module list. Compare `system-path`
     `drvPath` with the helper's `targetSystemFor` for the same case.
   - **Output** one line per case, `equal` or `DIFFERS <seed> <vm>`; exit 1
     on any difference.
   - **Verify:** build it (cheap, under the flock). All six must be equal.
     If any case differs, report it with both `system-path` `chosenOutputs`
     orders (`nix derivation show`) before changing anything.

6. **§1, and `nixarchy-hardware.nix`.**
   - **(a)** In a committed baseline, wrap `nixosModules.nixarchy` in
     `{ imports = [ (import ./modules/nixos.nix inputs) ]; }` (#1176's
     break): **the check must stay green** (the property).
   - **(b)** Move `instrumentation` back to depth 0 in the helper: **the
     check must go red,** naming the instrumented cases.
   - **(c)** Both together: red. That is today's trap, reproduced.

   Show `grep` that each break landed; capture the outputs. If (a) goes red,
   report it rather than adjust: it means a depth still differs.
   - Also try the real `nixarchy-hardware.nix` content `install.sh` writes for
     a QEMU guest (`write_hardware_modules`, `:1955`) in the VM side. Record
     whether `system-path` changes; if it does, add the same file to the
     helper's seed at depth 1.

7. **`tests/AGENTS.md`, and the PR.**
   - One paragraph, near the install checks' section: the seed mirrors the
     template's depths, why (#1176), and that `checks.install-seed-shape`
     enforces it.
   - Run `nix fmt -- --ci`, statix and deadnix. Check
     `git merge-base origin/main HEAD` is current, and
     `git show --stat` lists only this task's files.
   - **The PR body:**
     - links intent, spec and plan;
     - the six-case output, the reds (a/b/c), and the step-6
       `nixarchy-hardware.nix` result;
     - says which steps the coder did;
     - uses `closes #1179`;
     - contains no skip-CI marker.
   - **CI's `install`, `free-space`, and the nightly's `install-encrypted`**
     are the end-to-end proof.

## Tests

| step | command | expected |
|---|---|---|
| 1-4 | `nix eval` of each test's `drvPath`; `testScript` diff | evaluates; script unchanged but for interpolation |
| 5 | `checks.install-seed-shape` | six `equal` |
| 6 | breaks (a), (b), (c) | green, red, red |
| CI | `install`, `free-space`; nightly `install-encrypted` | green |

## Rollback

Revert the squash commit. The three tests return to their own seed copies,
and the check goes with them.

## Deviations (2026-10-03, during implementation)

- **Step 1, the helper's parameters:** `install-encrypted`'s configuration
  values differ: autologin on, and
  `boot.initrd.secrets."/etc/shadow" = "/var/lib/nixarchy/initrd-shadow"`.
  The helper takes them the way the template does, from `install.sh`'s
  placeholders: `encrypt ? false` drives `services.displayManager.autoLogin.enable`
  (`@autologin@` follows `@encrypt@`), and `recoverySecret ? false` adds the
  `initrd.secrets` entry (`@recoverysecret@`). Found by the coder agent at
  step 1.
- **Step 3, free-space gains the instrumentation `grep`:** its cp/sed never
  checked that the sed landed, although its comment said "Identical to
  checks.install". The shared `instrumentScript` carries `install`'s
  `grep -q test-instrumentation`, so free-space now asserts it too (strictly
  stronger; it makes the comment true). Found by the coder agent.
- **Step 4, one source for the instrumentation (option C):** `install-encrypted`
  writes its console and plymouth settings into the same `test-instrumentation.nix`
  the VM imports, so a separate `extraInstrumentation` module would have been a
  second copy to keep in step by hand. The helper takes `extraInstrumentationText`,
  renders the one file (`etcInstrumentation`), and the seed imports that same
  text via `builtins.toFile` at depth 2. Seed and VM load byte-identical
  instrumentation. Measured in one tree: the encrypted seed's toplevel `drvPath`
  is unchanged by the port, and install's plain and instrumented seeds too.
- **Step 6, break (b) alone stays green:** with nixarchy's module at depth 0,
  instrumentation at depth 0 or 2 gives the same order. Only (c), the old seed
  shape plus #1176's wrap, splits seed from VM, which is exactly #1176. (a),
  the wrap with the new helper, stays green: the property. (d) the real
  `nixarchy-hardware.nix` (AMD and Intel) does not change `system-path`, so it
  stays out of the seed.
