---
status: approved
issue: 1076
spec: spec/2026-09-30-1076-codereview-criticals.md
---

# Plan: Fix the code review's critical findings, and the highs in the same places, in one PR

Worktree `/mnt/data/vmtest/wt-crit`, branch `fix/1076-codereview-criticals`.
Line numbers and quotes below were checked against the tree at `abb602a`.

## Approved decisions

Carried over from the spec. A coder should not need to open it.

**Scope:** #1076, #1077, #1078, #1079, #1082, #1083 and #1084, in one PR. Out of scope:

- #1085, #1086 and the medium findings;
- retrying a free-space install (it refuses on its own first-attempt partitions);
- baking free-space reference variants.

Both open spec decisions were taken at their defaults:

- offline `--from` is in scope (D);
- the free-space retry is out of scope.

**A. #1076: the guest never shares the directory that holds `current`.**

- `modules/microvm/guest.nix`'s read-write `hostdir` share changes from
  `source = "."` to `source = "share"`.
  - The path is relative, and each runner resolves it against its own
    working directory.
  - The mount point stays `/mnt/host`, so templates are unchanged.
- **Declarative machines:** nixarchy adds a
  `systemd.tmpfiles.settings."10-nixarchy-microvm"` entry per machine for
  `${microvm.stateDir}/<name>/share`, as `microvm:kvm` mode `0770`.
- **Imperative VMs:** `pkgs/microvm.nix` runs `mkdir -p "$dir/share"` in
  `create_vm` and in `exec_vm`, which also migrates existing VMs. The
  `hostname` file moves into `share/`.
- Nothing is migrated or deleted. Release note: files a guest wrote at the old
  root stay where they are, and the user moves them into `share/` by hand. A
  missing `allow-hosts` fails closed.
- Docs to update: `docs/manual/sandboxes.md`, the header of
  `templates/agent.nix`, and guest.nix's comment claiming the `persistent`
  template writes to `/mnt/host` (it uses `home.img`).
- Upstream microvm.nix is not patched.

**B. #1083.**

1. `modules/services/microvm.nix:201` becomes
   `microvm.host.enable = lib.mkDefault (config.microvm.vms != { });`.
   - The issue's `mkIf … (mkDefault true)` is wrong: it leaves upstream's
     `default = true` on and turns the `mvOff` rows red.
   - The option text says that someone who runs only imperative `microvm -c`
     machines sets `microvm.host.enable` themselves.
2. `modules/nixos.nix:235`: delete `inputs.hyprland.nixosModules.default`.
   - Fix the comment at `:975-982`, which credits the `mkDefault` to the
     wrong module.
   - Release note: a Mode A user who set that module's options
     (`plugins`, `settings`, `extraConfig`, `topPrefixes`, `bottomPrefixes`)
     must import the module themselves.
3. `modules/microvm/templates/agent.nix`:
   - `users.users.dev.extraGroups = lib.mkForce [ ];`, which drops wheel;
   - the DHCP rule becomes
     `udp sport 68 udp dport 67 ip daddr { 10.0.2.2, 255.255.255.255 } accept`.
     The issue's "gateway only" would drop the broadcast DISCOVER.
   - `agent-claude` inherits both.
   - Update `sandboxes.md`.
4. `modules/services/microvm.nix:242` becomes
   `services.openssh.enable = lib.mkDefault (m.sshPort != null);`.

**C. #1077.**

- `ask_identity`: when `--from` is set, `hostname=$from_host` and no hostname
  prompt.
- `main`: after argument parsing, `validate_hostname "$from_host"`. This is
  #1098's low item, which this PR references but does not close.

**D. #1078 and offline `--from`.** `run_install` copies the baked reference
system only when `disk_mode = whole` **and** `from_repo` is empty. Otherwise it
builds, and logs why.

- Offline free-space then builds. If the image lacks something,
  `rescue_build`'s existing message applies.
- **Named hole:** whether an offline free-space build completes needs a VM.
  That is the `off-free` cell of `tests/install-matrix.py`, which no PR runs.

**E. #1084.**

1. `install_flake_dir` copies instead of moving (see P8 for the exact form).
2. The eight `exit`s in the phase chain become `return 1`:
   - six in `partition_free_space`: `:1457`, `:1463`, `:1475`, `:1492`,
     `:1499`, `:1517`;
   - `format_disk` `:1559`;
   - `reuse_baked_initrd` `:1756`.

   The callers check them: `partition_free_space || return 1` at `:1566`, and
   `reuse_baked_initrd … || return 1` at `:1643`. `nixos-generate-config` at
   `:1640` also gains `|| return 1`.
3. A new `confirm_repo_disks`, called after `finish_clone` and before
   `preflight_build`, for `--from` with an existing host:
   - evaluates the disko disks' `device`s;
   - prints `lsblk NAME,SIZE,MODEL,SERIAL` for each;
   - refuses a missing device or the boot medium;
   - asks `gum confirm` when interactive. An answers file never prompts,
     because the file is the consent.

**F. #1079.**

1. `read_answers`:
   - a comment is a line whose first non-space character is `#`;
   - CRLF is stripped;
   - the secret keys (`password`, `luks_passphrase`, `recovery_passphrase`)
     are kept verbatim, trailing spaces and `#` included (see P1 for the
     non-secret keys);
   - the help text at `:178` is updated.
2. `printf '%s' "$x" | mkpasswd -m sha-512 -s` at `:650`, `:702`, `:1151` and
   `:1167`. `-s` exists in the ISO's whois 5.5.23 and gives the same hash.
3. `connect_wifi` `:429`:
   `printf '%s\n' "$pw" | nmcli --ask device wifi connect "$ssid"`.
   - This is proven on `wifi-hwsim`.
   - The fallback, if it fails there: `nmcli connection add … wifi-sec.key-mgmt wpa-psk`,
     then `nmcli connection up … passwd-file <(…)`.
4. `curl` `:1100`: add `--proto =https --proto-redir =https`.
5. An EXIT trap removes the fetched answers file (see P2 for its exact form).

**G. #1082.** `.github/scripts/pr-touches-build.sh:191`:

- `tests/hardware-configuration.nix|tests/test-instrumentation.nix)`, which
  are two files that do not exist, becomes
  `tests/with-vm-cleanup.nix|tests/vm-cleanup.py)`;
- the comments at `:168`, `:181-183` and `:210` are corrected;
- `tests/install-gate.nix` covers it.

This is CI-gate territory (§11). The owner merges it, and has authorised
merging when green.

**Checks.** Each one is proven red with its fix removed, then green (§1).
They sit at the cheapest layer that can see the bug:

- `checks.options` for A, B1–B4;
- runCommand stubs for C, D, E and F;
- `install-gate` for G;
- VMs only where nothing else reaches: `microvm-boot`, `wifi-hwsim`, and the
  install checks in CI.

## Found while planning: decisions for plan approval

Each item below has a default, and the steps implement the default. Approving
the plan approves them.

**P1: the manual's answers-file example uses trailing comments, so "a `#`
elsewhere is data" would break it for every key.**
`docs/manual/unattended-installs.md:17,22,23` show `disk_mode=whole  # or free`
and `password=hunter2  # plaintext…`. Under the spec's literal rule,
`disk_mode` would become `whole             # or free…` and fail validation.

*Default:*

- A trailing `#…` is still stripped for **non-secret** keys. No non-secret
  value can contain `#`: a device, hostname, username, timezone, keymap,
  yes/no, or a `$6$` crypt hash, whose alphabet is `./0-9A-Za-z`.
- The three secret keys are verbatim.
- The manual moves its comments onto their own lines. Its `password=`
  example is exactly the line that would now carry a comment into the
  password.
- **Guard (added at plan approval by the owner):** a secret value containing
  whitespace followed by `#` is refused with exit 2 and "looks like a trailing
  comment -- move it to its own line". An answers file copied from the old
  manual would otherwise install with the comment inside the password and lock
  the user out. Ceiling: a real secret containing ` #` is refused too; accepted
  as rare.

**P2: the spec's `trap 'rm -f "$tmp"' EXIT` would remove nothing.**
`tmp` is `local` to `resolve_answers`, and the single-quoted trap expands it at
exit, when it is out of scope and empty.

*Default:* set `answers_fetched=$tmp` before `curl` and use
`trap 'rm -f "$answers_fetched"' EXIT`. That variable is global (`:113`), and
`main` already clears the file at `:2831`.

**P3: dropping the Hyprland module also drops its
`environment.pathsToLink = [ "/share/hypr" ]`.**
The module sets it under `programs.hyprland.enable`. Today every nixarchy
machine links `/run/current-system/sw/share/hypr`, which holds the lua stubs,
the wallpapers and `hyprlock.conf`. Nothing in this repository reads it (it
was grepped), but it is behaviour that ships.

*Default:* keep it, by adding `"/share/hypr"` to nixarchy's own `pathsToLink`
at `modules/nixos.nix:1186`, under `cfg.enable`. A nixarchy-off host then gets
nothing, which is the point.

**P4: `tests/install-gate.nix` asserts the two nonexistent names.**
The cases "the shared hardware fixture does" and "the shared instrumentation
does" turn red once G lands. They encoded the arrangement, not the property
(§1 read backwards).

*Default:* retarget both cases to `tests/with-vm-cleanup.nix` and
`tests/vm-cleanup.py`, rather than adding cases beside them. Say so in the PR.

**P5: `wifi-hwsim` cannot make `nmcli device wifi connect` exit 0.**
The AP has no DHCP server. Its own comment (`:136-145`) records exit 4 after
46 s, following a successful handshake.

*Default:* the new case asserts the property in question: nmcli read the
piped password. It checks that hostapd's `EAPOL-4WAY-HS-COMPLETED` count
grows after the piped connect. nmcli's exit status is ignored. No DHCP server
is added (that would test dnsmasq).

**P6: `checks.microvm-template` boots nothing, so it cannot prove the
declarative share.** The spec labels it "VM (existing)", but its header says
"Builds a runner and reads it. Boots nothing." If the share directory were
missing, qemu's `-fsdev path=share` would fail, so no declarative machine
would start. Only a booted host can see that.

*Default:*

- `microvm-template` gains the imperative assertions: the runner's
  `path=share`, and `share/hostname` after a stub run.
- `checks.microvm-boot` (nightly-only, a declarative machine, 113 s on p620
  with KVM per its header) gains a host-side probe.
- [C] runs `microvm-boot` locally, since it is cheap on p620.

**P7: no `installer-flake-dir` check exists.**

*Default:* put these where their neighbours already live:

- **E1 and E2's cases:** `tests/installer-store-space.nix`, which already
  holds the `format_disk`, `partition_free_space` and `verify_subvolume_mounts`
  cases.
- **C's case and E3's cases:** `tests/installer-from-repo.nix`, the `--from`
  check. The spec's new `tests/installer-identity-from.nix` is dropped; it
  would be one file for one function of the same mode.
- **New files:** only D (`installer-baked-guard.nix`) and F
  (`installer-answers.nix`).

**P8: `cp -a "$work" /mnt/etc/nixos` nests on an existing directory.**
Written that way, it would produce `/mnt/etc/nixos/<tmpname>`.

*Default:* `mkdir -p /mnt/etc/nixos && cp -a "$work/." /mnt/etc/nixos/`, with
the status checked.

**P9: `install-encrypted` is nightly-only.** The spec's Risks list says it runs
on this PR, but it does not: it is in `nightly_only`
(`.github/scripts/generated-checks.sh:76`).

*Default:*

- The PR says so.
- Its first run is the nightly after the merge, and [O] reads it (step V6).
- `install`, `free-space` and `installer-refusal` do run on the PR, because
  `installer/install.sh` changes and `pr-touches-build` routes that change
  there.

**P10: observation, no decision needed.** In a declarative guest, `dev`
(uid 1000) probably cannot write a `microvm`-owned 9p root as itself. The same
was true of the old `0755 microvm` state directory, so this is not a
regression.

- Guest root can write it, and the allowlist oneshot runs as root.
- The `microvm-boot` probe uses `sudo` so that it does not depend on this.
- If the owner wants `dev` to write there, that is a separate change
  (`microvm.shares`' `securityModel`).

## Who does what

- **[O]** is the orchestrator (Opus, the session). It does all git and GitHub
  work: commit, push, PR and merge. It reads the agent bus, waits on CI and
  reads its logs.
- **[C]** is the `coder` agent (Sonnet). It edits files, `git add`s new files
  (a flake sees only tracked files, §5), and runs builds.
  - It never commits, stashes, resets, rebases, checks out or pushes.
  - Break proofs follow the procedure in "Break proofs" below. It never uses
    `git checkout` (§5).

## Rules for every step

- **Before any local build:**
  `gh -R olafkfreund/nixarchy run list --limit 10 --json status -q '[.[]|select(.status!="completed")]|length'`
  must print `0`.
  - If it does not, wait. Never start "just a small one" (§6).
  - p620 hosts all four runners and is a desktop in use.
- **Build by pinned derivation:**
  `drv=$(nix eval --raw .#checks.x86_64-linux.<name>.drvPath) && nix build "$drv^*" -L`.
  - Evaluate after the tree is in the state you mean (§5).
  - Never pipe a build whose status you need (§1). Use
    `set -o pipefail` or no pipe.
- **`checks.options`** takes about 13 GB and 8 min. Run it alone, with CI
  idle, and as the **last** local build (step V5).
- **After every `.nix` edit:** run `nix fmt`, then `git diff --stat`.
  - A hook may have run `nixpkgs-fmt` (§5, #897). A three-line edit showing
    hundreds of lines means `nix fmt` must run again.
  - Before handing back, `nix fmt -- --ci` must be clean.
- **Inside Nix `''` strings:**
  - no new heredocs; use `printf '%s\n'` (§5);
  - write bash `${x}` as `''${x}`;
  - never write two adjacent single quotes.
- **Never `| grep -q`.** Grep a file, a here-string or `[[ ]]`.
  `checks.grep-q-pipefail` enforces this (#1060).
- **New checks** are explicit `checks.<name>` entries in `flake.nix`, directly
  after `installer-offline-rescue` (`flake.nix:1980-1985`), in the same shape
  as `installer-network`. No workflow edit: the generated step builds them (§4).
- **Commit trailers:**
  - [C]'s work, committed by [O]:
    `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>` and
    `Claude-Session: https://claude.ai/code/session_017VFe59s7BspTamgenHc1P5`;
  - [O]'s own commits: `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`
    and the same `Claude-Session`.
- **Subjects** are full sentences with no conventional prefix (§8).
- **No skip-CI marker, literal or quoted,** anywhere in a commit or the PR
  body (§8).
- **While implementing,** [C] names the step it is executing. A deviation from
  this plan is reported to [O], who updates `plan/` in the same commit as the
  code.

## Steps

### Step 0 [O]: start

1. **Check the base.**
   - `git -C /mnt/data/vmtest/wt-crit fetch origin && git -C /mnt/data/vmtest/wt-crit status`.
   - If `origin/main` moved past `9a225a4`, rebase the branch onto it and
     read the status (§5).
   - Then check `git merge-base origin/main HEAD`.
2. **Read `#nixarchy-agents`** (`read_new`). Carry anything relevant into the
   PR body (§9).
3. **Start one `coder`** with this plan's path and "execute A1". Send each
   later step to the same agent with `SendMessage`.

### A. #1076: the MicroVM share

**A1 [C]: `modules/microvm/guest.nix`.**

Replace the comment and share at lines 35-52. The block starts
`# The second half of "the name is a directory, never a Nix argument".` and
ends at the `hostdir` attrset. New text:

```nix
      # The per-VM share, and NOT the VM's own directory (#1076). That
      # directory holds `current`, the runner the host executes -- as root in
      # upstream's ExecStopPost for a declarative machine, as the user in
      # `nixarchy vm stop` -- so a guest able to write it could replace what
      # the host runs. `share` is relative: lib/runners/qemu.nix writes it into
      # `-fsdev ...,path=` verbatim, so each runner resolves it against its own
      # working directory. modules/services/microvm.nix (tmpfiles) and
      # pkgs/microvm.nix (mkdir) create it. The `persistent` template keeps its
      # /home in `home.img` beside this directory, not in it.
      {
        tag = "hostdir";
        source = "share";
        mountPoint = "/mnt/host";
        proto = "9p";
      }
```

- The `tag` stays `hostdir`: upstream names the mount unit after the tag.
- Lines 89-94, the hostname comment: replace "the runner's own working
  directory -- already shared at /mnt/host above -- carries" with "the per-VM
  share at /mnt/host (`<vm dir>/share` on the host) carries".

Traps: §5 formatter hook.

**A2 [C]: `modules/services/microvm.nix`, the tmpfiles rule.** Inside
`(lib.mkIf wanted { … })`, after the `users.users = …;` block (line 207):

```nix
      # Why: modules/microvm/guest.nix -- the guest's /mnt/host is <state>/share,
      # never <state> itself (#1076). kvm, so the user can drop allow-hosts.
      systemd.tmpfiles.settings."10-nixarchy-microvm" = lib.mapAttrs' (
        name: _:
        lib.nameValuePair "${config.microvm.stateDir}/${name}/share" {
          d = {
            user = "microvm";
            group = "kvm";
            mode = "0770";
          };
        }
      ) svc.machines;
```

The parent `<state>/<name>` is created by upstream's `install-microvm-<name>`
(`mkdir -p` and `chown microvm:kvm .`), so no second rule is needed.

**A3 [C]: `pkgs/microvm.nix`.**

- `create_vm`, lines 256-258: after `mkdir -p "$dir"`, add
  `mkdir -p "$dir/share"`, and change `echo "$name" > "$dir/hostname"` to
  `echo "$name" > "$dir/share/hostname"`.
- `exec_vm`, lines 331-335, becomes:
  ```bash
        exec_vm() {
          # The guest sees share/ only (#1076); made here too, for VMs created before it.
          mkdir -p "$dir/share"
          echo "$name" > "$dir/share/hostname"
          cd "$dir"
          exec ./current/bin/microvm-run
        }
  ```
- Header, lines 29-30: "reads the runtime hostname from a file dropped there"
  becomes "reads the runtime hostname from `share/hostname`, the only part of
  that directory the guest can see (#1076)".

Traps: this is a Nix `''` string, so no `${`.

**A4 [C]: `tests/microvm-template.nix`, the imperative half.**

1. In the per-template loop, after the `mount_tag=ro-store` check (line 105-108):
   ```bash
      # #1076: the read-write share is share/, never the VM directory holding current.
      if ! grep -qF 'path=share,' "$run"; then
        echo "${name}: bin/microvm-run's hostdir share is not path=share -- the guest could write current" >&2
        fail=1
      fi
   ```
   Inside the Nix string, `${name}` is Nix interpolation, as in the
   neighbouring lines. It is deliberate.
2. After the `run.marker` wait block (the `fi` that ends the "the first 'run'
   never reached the stub guest" branch, about line 406):
   ```bash
    if [ "$(cat "$HOME/.local/state/nixarchy/microvm/sandbox/share/hostname" 2>/dev/null)" != sandbox ]; then
      echo "run did not write share/hostname -- the guest's /mnt/host has no name to read (#1076)" >&2
      fail=1
    fi
   ```

Verify:
`drv=$(nix eval --raw .#checks.x86_64-linux.microvm-template.drvPath) && nix build "$drv^*" -L`
is green. It boots nothing and fetches the guest closures from the cache.

**A5 [C]: `tests/microvm-boot.nix`, the declarative half (P6).** After
`machine.wait_until_succeeds("${ssh} true", timeout=1200)`:

```python
    # #1076: the guest's /mnt/host is <state>/share, never the state directory
    # holding `current`. sudo, because the 9p root is microvm's, not dev's.
    machine.succeed("${ssh} sudo touch /mnt/host/probe-1076")
    machine.succeed("test -f /var/lib/microvms/sandbox/share/probe-1076")
    machine.fail("test -e /var/lib/microvms/sandbox/probe-1076")
    owner = machine.succeed("stat -c '%U:%G %a' /var/lib/microvms/sandbox/share").strip()
    assert owner == "microvm:kvm 770", f"#1076: the share is {owner!r}, not microvm:kvm 770"
```

This is run locally in V3.

### B. #1083: Mode A and MicroVM isolation

**B1 [C]: `microvm.host.enable`**, `modules/services/microvm.nix`.

- Replace line 201 with
  `microvm.host.enable = lib.mkDefault (config.microvm.vms != { });`.
- The comment above it (lines 198-200) gains: "Your own `microvm.vms` count
  too (#1083): a Mode A user's machines keep their host whether or not
  nixarchy's service is on."
- Header lines 31-33: replace "`machines != { }` on top of the service being
  wanted: a user who turns the service on but declares no machine gets
  nothing running" with "`microvm.vms != { }`, whoever declared them (#1083):
  no machine, nothing running".
- `enable`'s description, lines 59-63: after "which this module turns on for
  you only once you declare a machine below", add "(or any `microvm.vms` of
  your own). Running only imperative `microvm -c` machines, with none
  declared? Set `microvm.host.enable = true` yourself."

**B2 [C]: the Hyprland module**, `modules/nixos.nix`.

- Delete line 235, `    inputs.hyprland.nixosModules.default`.
- Replace the comment at lines 975-982 (inside `hyprland = {`) with:
  ```nix
        # Plain priority, deliberately NOT mkDefault like everything else
        # here: Omarchy *is* Hyprland, so nixarchy on with Hyprland off is a
        # contradiction rather than a preference, and replacing the
        # compositor a whole desktop is written against is what lib.mkForce
        # is for. These are nixpkgs' options. hyprwm's NixOS module, which
        # set `package` at mkDefault on every machine importing nixarchy,
        # is not imported (#1083); only its packages are.
  ```
- P3, line 1186: `pathsToLink = [ "/share/omarchy" ];` becomes
  `pathsToLink = [ "/share/omarchy" "/share/hypr" ];`. After the #1069
  comment above it, add one line: "/share/hypr is what hyprwm's module linked
  under programs.hyprland.enable (its lua stubs); kept when that import went (#1083)."
- `docs/internals/flake.md`, the section "Hyprland from hyprwm…": after the
  table's closing paragraph (the one ending "…where waiting on a nixpkgs bump
  is not."), add:
  > **Its packages, not its NixOS module (#1083).** The module set
  > `programs.hyprland.package` at `mkDefault` on every machine that imported
  > nixarchy, including one with nixarchy off. nixarchy sets `package` and
  > `portalPackage` itself under `programs.nixarchy.enable`, and links
  > `/share/hypr` as the module did. A configuration that uses the module's
  > own options (`plugins`, `settings`, `extraConfig`, `topPrefixes`,
  > `bottomPrefixes`) imports `inputs.hyprland.nixosModules.default` itself.

Verify: `nix eval --raw .#nixosConfigurations.vm.config.system.build.toplevel.drvPath`
evaluates. `checks.options` in V5 does the rest.

**B3 [C]: the agent template**, `modules/microvm/templates/agent.nix`.

- After `users.users.tinyproxy.uid = proxyUid;` (line 105):
  ```nix
    # No wheel (#1083): `sudo nft flush ruleset` would undo the whole filter.
    # mkForce because guest.nix's list merges; agent-claude imports this file.
    users.users.dev.extraGroups = lib.mkForce [ ];
  ```
- Replace lines 205-208 (the DHCP comment and `udp dport 67 accept`) with:
  ```nix
          # DHCP, to SLiRP's server only (#1083): a bare `dport 67` let any uid
          # send to any address on 67. 255.255.255.255 for the renewals that
          # broadcast; the first DISCOVER leaves on a packet socket nft never sees.
          udp sport 68 udp dport 67 ip daddr { 10.0.2.2, 255.255.255.255 } accept
  ```
- Header lines 5-10: "one directory at /mnt/host" becomes "one directory at
  /mnt/host (the VM's `share/`, never the directory holding its runner,
  #1076)".
- Lines 43-48: "a plain-text file the caller drops in the VM's own directory"
  becomes "…drops in the VM's `share/` directory".
- `networking.nftables.checkRuleset` validates the syntax at guest build, so
  A4's `microvm-template` build proves the rule parses.

**B4 [C]: SSH**, `modules/services/microvm.nix:242`:
`services.openssh.enable = lib.mkDefault (m.sshPort != null);`. Extend the
comment above it (239-241) with: "mkDefault, so a machine's own `modules` can
turn sshd on without a port (#1083)."

**B5 [C]: `tests/options.nix`, covering A and B.**

1. **A new fixture, `modeAOff`,** directly after `adopter` (ends line 1943):
   ```nix
    # Mode A with nixarchy switched OFF: the module imported into somebody's own
    # configuration and nothing enabled. What that must leave alone (#1083).
    modeAOff = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        inputs.self.nixosModules.nixarchy
        {
          boot.loader.grub.enable = false;
          fileSystems."/" = {
            device = "/dev/null";
            fsType = "ext4";
          };
          system.stateVersion = "25.05";
        }
      ];
    };
   ```
2. **Two machines added to `mvOn`'s `machines`,** after `plain`. They are
   added to the existing evaluation, not a new host evaluation (§12, #747's
   memory note):
   ```nix
          # #1083: the agent template's rules and groups, from a real guest eval.
          agent = {
            template = "agent";
          };
          # #1083: a machine's own sshd wins over the sshPort-derived default.
          ownssh = {
            template = "shell";
            modules = [ { services.openssh.enable = true; } ];
          };
   ```
3. **`microvmProblems`:** append to the expression (after the `mvInvariantBig`
   `storeOnDisk` line):
   ```nix
    ++ (
      let
        sd = mvOn.microvm.stateDir;
        plain = mvVm mvOn "plain";
        agent = mvVm mvOn "agent";
        rules = pkgs.lib.splitString "\n" agent.networking.nftables.ruleset;
        rule = mvOn.systemd.tmpfiles.settings."10-nixarchy-microvm"."${sd}/plain/share".d or null;
      in
      pkgs.lib.optional (builtins.any (
        s:
        builtins.elem s.source [
          "."
          "${sd}/plain"
        ]
      ) plain.microvm.shares) "#1076: a guest share is the VM's own directory, which holds the `current` the host executes."
      ++ pkgs.lib.optional (
        rule == null || rule.user != "microvm" || rule.group != "kvm" || rule.mode != "0770"
      ) "#1076: no tmpfiles rule makes ${sd}/plain/share microvm:kvm 0770, so /mnt/host has nothing to mount."
      ++ pkgs.lib.optional (builtins.elem "wheel" agent.users.users.dev.extraGroups) "#1083: the agent template's dev is in wheel, so sudo can flush the egress ruleset."
      ++ pkgs.lib.optional (builtins.any (
        l: pkgs.lib.hasInfix "dport 67" l && !(pkgs.lib.hasInfix "daddr" l)
      ) rules) "#1083: the agent template accepts udp dport 67 to any address."
    )
   ```
   Change the builder's heading for this branch (line ~3011) from
   `"the microvm closure invariant does not hold:"` to
   `"a microvm invariant does not hold:"`.
4. **Three cases** in `cases`, after `microvmTemplate` (ends about line 1716):
   ```nix
    # #1083: a Mode A user's own microvm.vms keep upstream's host on, whatever
    # nixarchy's service says; with no vms at all it stays off.
    microvmModeAKeepsHost = {
      on =
        (modeAOff.extendModules { modules = [ { microvm.vms.mine = { }; } ]; }).config.microvm.host.enable;
      off = modeAOff.config.microvm.host.enable;
    };

    # #1083: nixarchy off defines no programs.hyprland.package, so it sits at
    # nixpkgs' option default (priority 1500), not hyprwm's mkDefault (1000).
    hyprlandModeAUntouched = {
      on = modeAOff.options.programs.hyprland.package.highestPrio >= 1500;
      off = adopter.options.programs.hyprland.package.highestPrio >= 1500;
    };

    # #1083: a machine's own services.openssh.enable evaluates and wins; plain
    # assignment used to make it a conflicting-definition error.
    microvmSshYields =
      let
        r = builtins.tryEval (mvVm mvOn "ownssh").services.openssh.enable;
      in
      {
        on = r.success && r.value;
        off = (mvVm mvOn "plain").services.openssh.enable;
      };
   ```
   - `tryEval` catches the conflict because the merge `throw`s. A *missing*
     attribute it would not catch (§5); `ownssh` is declared above.

Verify: in V5, with `checks.options`.

Traps:

- Take §12's warning seriously. Grep `tests/options.nix` for `mvOn` before
  adding the machines. No existing case counts `mvOn`'s vms; only
  `microvmAutostart` reads names, and only `sandbox` and `plain`.
- The `modeAOff` evaluation is light (nixarchy off), and it is the only new
  host evaluation.

### C. #1077: `--from` owns the hostname

**C1 [C]: `installer/install.sh`.**

- `ask_identity`: replace the hostname loop (lines 720-725,
  `while :; do` / `hostname=$(gum input … "Hostname> ")` / … / `done`) with:
  ```bash
    if [ -n "${from_repo:-}" ]; then
      # --host names the machine, and clone_repo has already built $hostdir from
      # it. Asking again would ask a question whose answer disko ignores (#1077).
      hostname=$from_host
    else
      while :; do
        hostname=$(gum input --padding "$(ui_gum_pad)" --placeholder "nixarchy" --prompt "Hostname> ") || ui_abort
        hostname=${hostname:-nixarchy}
        why=$(validate_hostname "$hostname") && break
        gum style --foreground 1 "$why"
      done
    fi
  ```
  `${from_repo:-}`, because `tests/installer-store-space.nix`'s escape test
  extracts `ask_identity` under `set -u` with no `from_repo` defined.
- `main`: after the block `if [ -n "$from_host" ] && [ -z "$from_repo" ]; then … fi`
  (ends line 2801):
  ```bash
    # A directory name under hosts/ and a hostName both; the wizard's own rule (#1098).
    if [ -n "$from_host" ]; then
      local why
      why=$(validate_hostname "$from_host") || {
        echo "nixarchy-install: --host $from_host: $why" >&2
        exit 2
      }
    fi
  ```

**C2 [C]: `tests/installer-from-repo.nix` (P7).** Before the final
`[ "$fails" = 0 ]` / `touch $out` lines, using the file's `failed` helper:

```bash
    # ---- #1077: --from owns the hostname --------------------------------
    {
      sed -n '/^validate_username()/,/^}/p' ${installScript}
      sed -n '/^validate_hostname()/,/^}/p' ${installScript}
      sed -n '/^ask_identity()/,/^}/p' ${installScript}
    } > ai.sh
    grep -q '^ask_identity()' ai.sh || { echo "ask_identity is not in install.sh any more" >&2; exit 1; }
    mkdir -p zi/Europe
    : > zi/Europe/London
    for mode in from wizard; do
      (
        . ./ai.sh
        ui_screen() { :; }
        ui_gum_pad() { echo 0; }
        ui_widget_height() { echo 10; }
        ui_abort() { exit 130; }
        ask_password() { :; }
        ask_recovery() { :; }
        TZDIR=$HOME/zi
        gum() {
          printf '%s\n' "$*" >> "$HOME/gum-$mode.log"
          case "$*" in
            *Username*) echo alice ;;
            *Hostname*) echo someone-else ;;
            *filter*) cat > /dev/null; echo Europe/London ;;
          esac
        }
        from_repo="" from_host=alpha
        if [ "$mode" = from ]; then from_repo=file:///r; fi
        ask_identity
        printf '%s\n' "$hostname" > "$HOME/hostname-$mode"
      ) || failed "ask_identity ($mode) did not return"
    done
    [ "$(cat hostname-from)" = alpha ] || failed "--from: the typed hostname replaced --host alpha (#1077)"
    if grep -q Hostname gum-from.log; then failed "--from: a hostname was asked for, and disko would ignore it (#1077)"; fi
    [ "$(cat hostname-wizard)" = someone-else ] || failed "without --from the typed hostname is no longer used"
    sed -n '/^main()/,/^}/p' ${installScript} > main.sh
    grep -q 'validate_hostname "$from_host"' main.sh || failed "main does not validate --host (#1098)"
```

- The `*filter*` arm consumes stdin. Without that, the `find | … | gum filter`
  pipe can SIGPIPE under stdenv's `pipefail`.
- Check where the file keeps `$HOME`: it sets `export HOME=$PWD` at its top.

Verify: `checks.installer-from-repo` is green.

### D. #1078: the baked system only for a whole-disk, non-`--from` install

**D1 [C]: `run_install`**, `installer/install.sh:2557-2574`.

Replace `local baked_system=""` and the following `if [ -r "$baked" ]; then`
with:

```bash
  local baked_system="" why_not_baked=""
  # The baked system is the REFERENCE machine: whole-disk partition labels and
  # the template's host. A free-space install cuts other partitions, and one
  # that mounts labels it never created does not boot (#1078); --from installs
  # the repository's machine, not the reference.
  [ "$disk_mode" = whole ] || why_not_baked="a free-space install mounts partitions the image's system does not name (#1078)"
  [ -z "$from_repo" ] || why_not_baked="--from installs $from_repo's $hostname, not the image's reference machine"
  if [ -r "$baked" ] && [ -n "$why_not_baked" ]; then
    echo "nixarchy-install: building rather than copying the system this image carries: $why_not_baked."
    echo "nixarchy-install: on the offline image that is expected; if the image lacks something, the rescue below says so."
  elif [ -r "$baked" ]; then
```

The rest of the block is unchanged, down to its `fi`. Keep the comment above
`local baked=`, and add one line to its "What makes copying CORRECT" list:
"the layout: whole-disk only; see why_not_baked below."

**D2 [C]: the new file `tests/installer-baked-guard.nix`,** then `git add` it.

```nix
{ pkgs, installScript }:
# run_install's choice between the system the offline image carries and a
# build (#1078): the baked system is the whole-disk reference machine, so a
# free-space or --from install must build. nix and nixos-install are stubs;
# what is asserted is the --system nixos-install was handed.
pkgs.runCommand "nixarchy-installer-baked-guard"
  {
    nativeBuildInputs = [
      pkgs.gnugrep
      pkgs.gnused
    ];
  }
  ''
    # The reference file lives in /etc on the image. Point the extracted
    # function at one written here, and prove the rewrite landed.
    sed -n '/^run_install()/,/^}/p' ${installScript} > ri-orig.sh
    sed "s|/etc/nixarchy-reference-|$PWD/ref-|" ri-orig.sh > ri.sh
    grep -q "$PWD/ref-" ri.sh || { echo "run_install no longer reads /etc/nixarchy-reference-<encrypt>" >&2; exit 1; }
    printf '%s\n' /nix/store/baked-system > ref-false

    fails=0
    t() { # t <name> <want: baked|built> <disk_mode> <from_repo>
      rm -f install-args
      (
        . ./ri.sh
        NIX_FLAGS=()
        SUBSTITUTE_FLAGS=()
        SUBSTITUTERS=""
        TRUSTED_KEYS=""
        build_store_choice=live hostname=h encrypt=false
        disk_mode=$3 from_repo=$4
        nix() {
          case "$*" in
            *path-info*) return 0 ;;
            *--dry-run*) echo "these 0 paths will be fetched" ;;
            *--print-out-paths*) echo /nix/store/built-system ;;
          esac
        }
        rescue_build() { return 1; }
        nixos-install() { printf '%s\n' "$@" > install-args; }
        run_install
      ) > "ri-$1.out" 2>&1 || true
      got=none
      if grep -qx /nix/store/baked-system install-args 2>/dev/null; then got=baked; fi
      if grep -qx /nix/store/built-system install-args 2>/dev/null; then got=built; fi
      if [ "$got" = "$2" ]; then
        echo "  ok      $1 ($got)"
      else
        echo "  FAILED  $1: wanted $2, got $got"
        sed 's/^/            /' "ri-$1.out"
        fails=$((fails + 1))
      fi
    }
    t whole-disk baked whole ""
    t free-space built free ""
    t from-repo built whole file:///repo
    grep -q 'building rather than copying' ri-free-space.out || {
      echo "  FAILED  free-space: the log does not say why it builds"
      fails=$((fails + 1))
    }
    [ "$fails" = 0 ] || { echo "$fails case(s) failed (#1078)" >&2; exit 1; }
    echo "only a whole-disk install without --from copies the image's system"
    touch $out
  ''
```

- Write `""` for an empty argument, never two adjacent single quotes (Nix).
- Register it in `flake.nix` after `installer-offline-rescue`:
  ```nix
          # Why: tests/installer-baked-guard.nix
          installer-baked-guard = import ./tests/installer-baked-guard.nix {
            pkgs = pkgsFor.${system};
            installScript = ./installer/install.sh;
          };
  ```

Verify: `checks.installer-baked-guard` is green with 3 ok lines, and
`checks.test-registration` is green.

### E. #1084: the failure path

**E1 [C]: `install_flake_dir`** (line 1947, P8). Replace its first two lines:

```bash
  # Copied, not moved: $work is what format_disk builds the disko script from,
  # and a retry from the failure screen formats again from it (#1084).
  mkdir -p /mnt/etc/nixos
  cp -a "$work/." /mnt/etc/nixos/ || return 1
```

The `git init` and `git add` that follow are unchanged. `git init` is a no-op
on the copied `.git`.

**E2 [C]: no `exit` in the phase chain.**

- `partition_free_space`: each of `:1457`, `:1463`, `:1475`, `:1492`, `:1499`
  and `:1517` changes from `exit 1` to `return 1`.
- `format_disk`: `:1559` becomes `return 1`, and `:1566`, `    partition_free_space`,
  becomes `    partition_free_space || return 1`.
- `generate_hardware_config`:
  - `:1640-1641` gains `|| return 1` after
    `>"$hostdir/hardware-configuration.nix"`;
  - `:1643` becomes
    `reuse_baked_initrd "$hostdir/hardware-configuration.nix" || return 1`.
- `reuse_baked_initrd`: `:1756` becomes `return 1`.
- Where a message says "Reboot and retry" or "Start again", leave it. The
  failure screen offers both.
- Verify:
  `sed -n '/^partition_free_space()/,/^}/p;/^format_disk()/,/^}/p;/^reuse_baked_initrd()/,/^}/p' installer/install.sh > /tmp/claude-1000/pc.txt; grep -nE '^[[:space:]]*exit' /tmp/claude-1000/pc.txt`
  prints nothing. Use a scratch path, and never pipe into grep.

**E3 [C]: `confirm_repo_disks`.** Add it to `installer/install.sh` directly
after `finish_clone()` (ends line 1397):

```bash
# --from a machine the repository already describes: its disk-config.nix picks
# the disk, so name it before anything erases it (#1084). The boot medium and a
# disk this machine does not have are refused; an answers file is the consent,
# as --from's own warning in main() already treats it.
confirm_repo_disks() {
  [ "$from_host_exists" = true ] || return 0
  local devs dev real boot line
  devs=$(nix "${NIX_FLAGS[@]}" eval --raw \
    "$work#nixosConfigurations.$hostname.config.disko.devices.disk" \
    --apply 'd: builtins.concatStringsSep "\n" (map (x: x.device) (builtins.attrValues d))') || {
    echo "nixarchy-install: could not read which disks $hostname's disk-config.nix formats." >&2
    echo "  Nothing was written." >&2
    return 1
  }
  [ -n "$devs" ] || {
    echo "nixarchy-install: $hostname's disk-config.nix names no disk. Nothing was written." >&2
    return 1
  }
  boot=$(boot_medium)
  [ -z "$boot" ] || boot=$(readlink -f "$boot")
  echo "$from_repo's $hostname will ERASE:"
  while IFS= read -r dev; do
    real=$(readlink -f "$dev")
    if [ -n "$boot" ] && [ "$real" = "$boot" ]; then
      echo "nixarchy-install: $dev is the medium this installer booted from. Nothing was written." >&2
      return 1
    fi
    line=$(lsblk -dno NAME,SIZE,MODEL,SERIAL "$real" 2>/dev/null) && [ -n "$line" ] || {
      echo "nixarchy-install: $dev is not a disk on this machine. Nothing was written." >&2
      return 1
    }
    echo "  $dev  $line"
  done <<<"$devs"
  ui_interactive || return 0
  gum confirm --padding "$(ui_gum_pad)" "Erase these disks and install $hostname?" || return 1
}
```

In `main`, directly before `  preflight_build || exit 1` (line 2897), after
the dry-run block (a dry run touches no disk):

```bash
  confirm_repo_disks || exit 1
```

It is at top level, not in the chain, so `exit` is right here, as it is for
`preflight_build`.

**E4 [C]: `tests/installer-store-space.nix` (P7).** After the line
`echo "format_disk fails when disko does, and the backstop checks the ESP"`,
add the following. There are no new heredocs; the subshells run inline.

```bash
  # ------------------------------------------------------------------------
  # #1084: nothing in the phase chain may `exit`. install_attempts only draws
  # the failure screen (and its Retry) for a function that RETURNS.
  # ------------------------------------------------------------------------
  for fn in format_disk partition_free_space verify_subvolume_mounts \
    generate_hardware_config reuse_baked_initrd write_hardware_modules \
    install_flake_dir write_password_hash write_hostname run_install \
    rescue_build check_store_space chown_flake_dir carry_network_profiles \
    take_factory_snapshot; do
    sed -n "/^$fn()/,/^}/p" ${installScript} > lint-fn.sh
    [ -s lint-fn.sh ] || { echo "$fn is not in install.sh any more" >&2; exit 1; }
    if grep -nE '^[[:space:]]*exit([[:space:]]|$)|[;&|{][[:space:]]*exit([[:space:]]|$)' lint-fn.sh > lint-hits; then
      echo "$fn calls exit inside the install phases, so no failure screen and no retry (#1084):" >&2
      cat lint-hits >&2
      exit 1
    fi
  done
  echo "no install phase exits past the failure screen"

  # A failed partition_free_space stops format_disk before the disko script.
  rm -f disko-built
  (
    NIX_FLAGS=()
    work=/nonexistent hostname=h disk_mode=free luks_passphrase=pw
    . ./fd.sh
    findmnt() { return 1; }
    partition_free_space() { return 1; }
    nix() { touch disko-built; echo /nonexistent; }
    format_disk
  ) > fdfree.out 2>&1 && { echo "format_disk succeeded after partition_free_space failed (#1084)" >&2; exit 1; }
  [ ! -e disko-built ] || { echo "format_disk built the disko script after partition_free_space failed (#1084)" >&2; exit 1; }
  echo "a failed free-space partitioning stops format_disk before disko"

  # A failed nixos-generate-config stops generate_hardware_config.
  sed -n '/^generate_hardware_config()/,/^}/p' ${installScript} > ghc.sh
  test -s ghc.sh || { echo "generate_hardware_config is not in install.sh any more" >&2; exit 1; }
  rm -f rbi-called
  mkdir -p ghc-host
  (
    . ./ghc.sh
    hostdir=$PWD/ghc-host
    nixos-generate-config() { return 1; }
    reuse_baked_initrd() { touch rbi-called; }
    write_hardware_modules() { :; }
    generate_hardware_config
  ) > ghc.out 2>&1 && { echo "generate_hardware_config succeeded after nixos-generate-config failed (#1084)" >&2; exit 1; }
  [ ! -e rbi-called ] || { echo "generate_hardware_config went on after nixos-generate-config failed (#1084)" >&2; exit 1; }
  echo "a failed nixos-generate-config stops the hardware phase"

  # install_flake_dir twice: the retry needs $work, and must not nest the copy.
  sed -n '/^install_flake_dir()/,/^}/p' ${installScript} > ifd-orig.sh
  sed "s|/mnt/|$PWD/mnt/|g" ifd-orig.sh > ifd.sh
  grep -q "$PWD/mnt/etc/nixos" ifd.sh || { echo "install_flake_dir no longer writes /mnt/etc/nixos" >&2; exit 1; }
  mkdir -p flake-work/hosts/h
  printf '%s\n' '{ }' > flake-work/flake.nix
  (
    . ./ifd.sh
    git() { :; }
    work=$PWD/flake-work
    install_flake_dir && install_flake_dir
  ) > ifd.out 2>&1 || { echo "install_flake_dir failed on a retry (#1084)" >&2; cat ifd.out >&2; exit 1; }
  [ -f flake-work/flake.nix ] || { echo "install_flake_dir consumed the work tree; a retry cannot format again (#1084)" >&2; exit 1; }
  [ -f mnt/etc/nixos/flake.nix ] && [ ! -e mnt/etc/nixos/flake-work ] || {
    echo "install_flake_dir did not put the flake at /mnt/etc/nixos, or nested it on the retry" >&2; exit 1; }
  echo "install_flake_dir copies, so a retry still has its flake"
```

- `fd.sh` already exists at this point: it was extracted above.
- `NIX_FLAGS=()` is plain bash, and legal inside Nix `''`.
- The `( … ) && { …; exit 1; }` form is what keeps stdenv's `set -e` out of
  the expected failure.

**E5 [C]: `tests/installer-from-repo.nix`, the E3 cases.** After C2's block:

```bash
    # ---- #1084: --from names the disk before erasing it -----------------
    sed -n '/^confirm_repo_disks()/,/^}/p' ${installScript} > crd.sh
    grep -q '^confirm_repo_disks()' crd.sh || { echo "confirm_repo_disks is not in install.sh" >&2; exit 1; }
    crd() { # crd <name> <want: ok|refuse> ; env: ANSWERS, GUM_RC, DISK, BOOT
      rm -f "$HOME/gum-called"
      if (
        . ./crd.sh
        NIX_FLAGS=()
        work=/w hostname=alpha from_repo=file:///r from_host_exists=true
        answers_file=$ANSWERS
        nix() { printf '%s\n' /dev/disk/by-id/fake-a; }
        boot_medium() { printf '%s\n' "$BOOT"; }
        # Deviation (implementation): argument-aware, or `boot` and `real`
        # both resolve to $DISK and every case is refused as the boot medium.
        readlink() {
          case "$2" in
            /dev/disk/by-id/fake-a) printf '%s\n' "$DISK" ;;
            *) printf '%s\n' "$2" ;;
          esac
        }
        lsblk() { [ "$DISK" = /dev/gone ] || printf '%s\n' "vdb 64G QEMU_HARDDISK SERIAL-1076"; }
        ui_interactive() { [ -z "$answers_file" ]; }
        ui_gum_pad() { echo 0; }
        gum() { touch "$HOME/gum-called"; return "$GUM_RC"; }
        confirm_repo_disks
      ) > "crd-$1.out" 2>&1; then got=ok; else got=refuse; fi
      [ "$got" = "$2" ] || failed "confirm_repo_disks $1: wanted $2, got $got"
    }
    ANSWERS="" GUM_RC=1 DISK=/dev/vdb BOOT=/dev/sdz crd said-no refuse
    grep -q SERIAL-1076 crd-said-no.out || failed "confirm_repo_disks does not print the disk's serial"
    ANSWERS="" GUM_RC=0 DISK=/dev/vdb BOOT=/dev/sdz crd said-yes ok
    ANSWERS=/a GUM_RC=1 DISK=/dev/vdb BOOT=/dev/sdz crd unattended ok
    [ ! -e gum-called ] || failed "confirm_repo_disks prompted under an answers file"
    ANSWERS=/a GUM_RC=0 DISK=/dev/gone BOOT=/dev/sdz crd missing refuse
    ANSWERS=/a GUM_RC=0 DISK=/dev/sdz BOOT=/dev/sdz crd boot-medium refuse
    fc=$(grep -n '^    finish_clone$' main.sh | cut -d: -f1 | head -1 || true)
    cr=$(grep -n '^  confirm_repo_disks || exit 1$' main.sh | cut -d: -f1 | head -1 || true)
    pb=$(grep -n '^  preflight_build || exit 1$' main.sh | cut -d: -f1 | head -1 || true)
    [ -n "$fc" ] && [ -n "$cr" ] && [ -n "$pb" ] && [ "$fc" -lt "$cr" ] && [ "$cr" -lt "$pb" ] ||
      failed "main does not run confirm_repo_disks between finish_clone and preflight_build"
```

- `main.sh` was written by C2.
- The `grep | cut | head` shape is the file's existing precedent (`|| true`),
  and it is not `grep -q`.

Verify: `checks.installer-from-repo` and `checks.installer-store-space` are
green, and `nix build .#install` is green (`writeShellApplication` runs
shellcheck on the whole script).

### F. #1079: the installer's secrets

**F1 [C]: `read_answers`** (`install.sh:1119-1135`, P1). Replace the loop
head, from `lineno=$((lineno + 1))` through `value=${line#*=}`, with:

```bash
    lineno=$((lineno + 1))
    line=${line%$'\r'}
    line=${line#"${line%%[![:space:]]*}"}
    # A comment is a line that STARTS with # (#1079). The secrets below are
    # taken exactly as written, `#` and trailing spaces included; every other
    # key still drops a trailing `# ...`, since no such value can contain one.
    case $line in "" | \#*) continue ;; esac

    case $line in
      *=*) ;;
      *)
        echo "nixarchy-install: answers: line $lineno: not key=value: $line" >&2
        exit 2
        ;;
    esac
    key=${line%%=*}
    value=${line#*=}
    case $key in
      password | luks_passphrase | recovery_passphrase)
        case $value in
          *[[:space:]]\#*)
            echo "nixarchy-install: answers: line $lineno: $key looks like it has a trailing comment -- move it to its own line (a secret is taken exactly as written)" >&2
            exit 2
            ;;
        esac
        ;;
      *)
        value=${value%%#*}
        value=${value%"${value##*[![:space:]]}"}
        ;;
    esac
```

- `:1151`: `recovery_passphrase) recovery_hash=$(printf '%s' "$value" | mkpasswd -m sha-512 -s) ;;`
- `:1167`: `password_hash=$(printf '%s' "$password" | mkpasswd -m sha-512 -s)`
- The `usage()` text at `:178`: "one key=value per line, # for comments, no
  quoting:" becomes "one key=value per line, no quoting. A line starting with
  # is a comment; a trailing # comment is allowed except on password,
  luks_passphrase and recovery_passphrase, which are taken exactly as
  written, spaces included:".

**F2 [C]: `mkpasswd` via stdin.**

- `:650` → `password_hash=$(printf '%s' "$pw" | mkpasswd -m sha-512 -s)`
- `:702` → `recovery_hash=$(printf '%s' "$pw" | mkpasswd -m sha-512 -s)`

`printf` is a builtin, so no secret is in any argv. At `:1151` the pipe also
stops `-s` from reading the rest of the answers file.

**F3 [C]: `connect_wifi`**, `:429`. `nmcli device wifi connect "$ssid" password "$pw" || rc=$?`
becomes:

```bash
      # stdin, not argv (#1079): a password on nmcli's command line is in
      # /proc/<pid>/cmdline for every user on the live system.
      printf '%s\n' "$pw" | nmcli --ask device wifi connect "$ssid" || rc=$?
```

The pipe's status is nmcli's, because `printf` cannot fail here.

**F4 [C]: `curl`**, `:1100`. It becomes
`curl --fail --silent --show-error --location --proto =https --proto-redir =https --max-time 60 -o "$tmp" "$url" || {`.
Add one comment line above it: "Redirects too: https that redirects to http
would send the password in clear (#1079)."

*Deviation (implementation):* the trap adds a second `rm -f "$answers_fetched"`, so `installer-store-space.nix`'s line-order assertion now greps only inside `main()` (extracted with `sed -n '/^main()/,/^}/p'`), not the whole script.

**F5 [C]: the EXIT trap (P2).** In `resolve_answers`, directly after
`tmp=$(umask 077 && mktemp)` (`:1098`):

```bash
  # Gone on ANY exit, including read_answers refusing the file (#1079).
  # answers_fetched, not $tmp: the trap runs after this function's locals are
  # gone. ui_dashboard_start replaces it later; main() has removed the file by then.
  answers_fetched=$tmp
  trap 'rm -f "$answers_fetched"' EXIT
```

Then delete the old `answers_fetched=$tmp` at `:1110`, and move its comment
(`:1106-1109`) up to the new line.

**F6 [C]: the new file `tests/installer-answers.nix`,** then `git add` it.

```nix
{ pkgs, installScript }:
# read_answers, resolve_answers and the secret-handling lines around them
# (#1079): a `#` in a password is data, no secret reaches argv, the fetched
# copy is removed on a refused read, and https cannot redirect to http. The
# nmcli half is proven against a real radio in checks.wifi-hwsim.
pkgs.runCommand "nixarchy-installer-answers"
  {
    nativeBuildInputs = [
      pkgs.gnugrep
      pkgs.gnused
      pkgs.diffutils
    ];
  }
  ''
    sed -n '/^read_answers()/,/^}/p' ${installScript} > ra.sh
    grep -q '^read_answers()' ra.sh || { echo "read_answers is not in install.sh any more" >&2; exit 1; }
    sed -n '/^resolve_answers()/,/^}/p' ${installScript} > rs.sh
    grep -q '^resolve_answers()' rs.sh || { echo "resolve_answers is not in install.sh any more" >&2; exit 1; }

    fails=0
    failed() { echo "  FAILED  $1"; fails=$((fails + 1)); }
    ok() { echo "  ok      $1"; }

    # Each run: one secret, so mkpasswd is called once. argv and stdin to files.
    run() { # run <answers file>
      rm -f argv.log stdin.log got
      (
        . ./ra.sh
        mkpasswd() { printf '%s\n' "$*" >> argv.log; cat > stdin.log; echo HASHED; }
        device="" disk_mode="" encrypt="" luks_passphrase="" hostname="" username=""
        password_hash="" build_store_choice="" recovery_hash="" timezone="" keymap=""
        read_answers "$1"
        printf '%s|%s|%s|%s|%s|%s' "$hostname" "$disk_mode" "$keymap" "$password_hash" "$luks_passphrase" "$recovery_hash" > got
      ) > run.out 2>&1 || { failed "read_answers refused $1"; sed 's/^/            /' run.out; }
    }

    printf '%s\n' '# a comment' '   # an indented comment' 'hostname=box' 'disk_mode=whole   # or free' 'password=p#ss word ' > a1
    printf 'keymap=us\r\n' >> a1
    run a1
    printf '%s' 'box|whole|us|HASHED|p#ss word |' > want1
    if cmp -s want1 got; then ok "comments, CRLF, a trailing comment, and a # inside the password"; else failed "a1 parsed as: $(cat got)"; fi
    printf '%s' 'p#ss word ' > want-pw
    if cmp -s want-pw stdin.log; then ok "mkpasswd got the password on stdin, verbatim"; else failed "mkpasswd stdin was: $(cat stdin.log)"; fi
    if grep -qF 'p#ss' argv.log; then failed "the password is in mkpasswd's argv: $(cat argv.log)"; else ok "the password is not in mkpasswd's argv"; fi

    printf '%s\n' 'recovery_passphrase=r#cover ' > a2
    run a2
    printf '%s' 'r#cover ' > want-rc
    if cmp -s want-rc stdin.log; then ok "the recovery passphrase reaches mkpasswd on stdin, verbatim"; else failed "recovery stdin was: $(cat stdin.log)"; fi
    if grep -qF 'r#cover' argv.log; then failed "the recovery passphrase is in mkpasswd's argv"; fi

    # The P1 guard: the old manual's `password=hunter2   # plaintext` must be
    # refused, not installed with the comment inside the password.
    printf '%s\n' 'password=hunter2   # plaintext' > a3
    if ( . ./ra.sh; mkpasswd() { echo HASHED; }; read_answers a3 ) > a3.out 2>&1; then
      failed "a secret with a trailing comment was accepted (P1 guard)"
    elif grep -q 'trailing comment' a3.out; then
      ok "a secret with a trailing comment is refused"
    else
      failed "a3 refused for the wrong reason: $(cat a3.out)"
    fi

    # A read that refuses the file must not leave the fetched copy behind.
    rm -f fetched-path
    (
      . ./rs.sh
      curl() { while [ "$1" != -o ]; do shift; done; printf '%s\n' 'password=x' > "$2"; }
      answers_file=https://example.invalid/answers
      resolve_answers > /dev/null
      printf '%s\n' "$answers_fetched" > fetched-path
      exit 2
    ) || true
    p=$(cat fetched-path)
    if [ -n "$p" ] && [ ! -e "$p" ]; then ok "the fetched answers file is removed on exit"; else failed "the fetched answers file survives an exit before main removes it: $p"; fi

    # Static, where behaviour needs a radio or a network.
    grep -q -- '--proto =https --proto-redir =https' rs.sh || failed "curl can follow an https answers URL to plain http"
    [ "$(grep -c 'mkpasswd -m sha-512 -s' ${installScript})" = 4 ] || failed "not every mkpasswd reads its secret from stdin"
    if grep -q 'mkpasswd -m sha-512 "' ${installScript}; then failed "a secret is passed to mkpasswd as an argument"; fi
    sed -n '/^connect_wifi()/,/^}/p' ${installScript} > cw.sh
    grep -q 'nmcli --ask device wifi connect "$ssid"' cw.sh || failed "connect_wifi no longer pipes the password to nmcli --ask"
    if grep -q 'password "$pw"' cw.sh; then failed "connect_wifi puts the Wi-Fi password on nmcli's command line"; fi

    [ "$fails" = 0 ] || { echo "$fails case(s) failed (#1079)" >&2; exit 1; }
    touch $out
  ''
```

- Register it in `flake.nix` next to `installer-baked-guard`, in the same
  shape, under `# Why: tests/installer-answers.nix`.
- Nix traps in this file:
  - `$'\r'` does not appear in it;
  - `'   # an indented comment'` is one quoted word;
  - check that no line contains two adjacent single quotes.

Verify: `checks.installer-answers` is green. Also rerun `installer-store-space`
(its `rat.sh` drives `resolve_answers` with a curl stub that skips to `-o`,
and it must stay green) and `installer-failure-hints` (it greps
`connect_wifi`).

**F7 [C]: `tests/wifi-hwsim.nix` (P5).** Before the two final
`print(machine.succeed("nmcli device status"))` lines:

```python
    # #1079: the installer pipes the password to `nmcli --ask` so it never sits
    # in argv. Whether nmcli reads a piped password is nmcli's behaviour, so it
    # is proven here, on a real handshake. nmcli's own status is not the
    # signal: with no DHCP behind this AP it exits 4 after the handshake (above).
    machine.succeed("nmcli connection down test && nmcli connection delete test")
    before = int(machine.succeed("out=$(journalctl -u hostapd); grep -c EAPOL-4WAY-HS-COMPLETED <<<\"$out\" || true").strip() or 0)
    machine.execute("printf '%s\\n' supersecret | nmcli -w 20 --ask device wifi connect nixarchy-test")
    machine.wait_until_succeeds(
        f"out=$(journalctl -u hostapd); [ \"$(grep -c EAPOL-4WAY-HS-COMPLETED <<<\"$out\")\" -gt {before} ]",
        timeout=60)
```

- The Python string is inside a Nix `''` string: `'%s\\n'` reaches Python as
  `'%s\\n'`, which is `'%s\n'` in the shell.
- There are no heredocs.
- If this is red for a reason other than the password (V4 decides), apply
  F3's fallback: `nmcli connection add … wifi-sec.key-mgmt wpa-psk`, then
  `nmcli connection up … passwd-file <(printf '802-11-wireless-security.psk:%s\n' "$pw")`.
  [O] updates this plan in the same commit.

### G. #1082: the install gate

**G1 [C]: `.github/scripts/pr-touches-build.sh`.**

- Line 191: `    tests/hardware-configuration.nix|tests/test-instrumentation.nix)`
  becomes `    tests/with-vm-cleanup.nix|tests/vm-cleanup.py)`.
- Lines 167-169 ("reach `./hardware-configuration.nix` and
  `./test-instrumentation.nix` and nothing else") become "reach nothing under
  tests/ but `with-vm-cleanup.nix` and the `vm-cleanup.py` it reads".
- Lines 179-183: "and those three import only ./hardware-configuration.nix
  and ./test-instrumentation.nix from this directory. … the five names below"
  becomes "and install and free-space import only with-vm-cleanup.nix, which
  reads vm-cleanup.py (#1082: the two names this arm used to carry do not
  exist). … the five names below".
- Lines 208-210, the README arm: the same replacement as lines 167-169.

**G2 [C]: `tests/install-gate.nix` (P4).** Replace the two cases

```
    t "the shared hardware fixture does"       --install "tests/hardware-configuration.nix" true
    t "the shared instrumentation does"        --install "tests/test-instrumentation.nix" true
```

with

```
    # #1082: the helpers the install checks really import. The two names that
    # stood here named files that do not exist, and asserted that they did.
    t "the VM cleanup wrapper does"            --install "tests/with-vm-cleanup.nix" true
    t "the VM cleanup script does"             --install "tests/vm-cleanup.py" true
```

Verify: `checks.install-gate` is green.

### H. Docs and release notes [C]

**H1: `docs/manual/sandboxes.md`.**

- Line 35: "a per-VM directory under it, but the guest can write everything
  under `/mnt/host`" becomes "a `share/` directory inside each VM's own, and
  the guest can write everything under `/mnt/host`".
- Line 95: "in `wheel`" becomes "in `wheel` (not in the `agent` templates;
  see below)".
- Line 134: the path becomes
  `~/.local/state/nixarchy/microvm/review-bot/share/allow-hosts`. The
  surrounding text says `share/` is what the guest sees at `/mnt/host`.
- Lines 170-173, "Survive root inside the guest": rewrite. `dev` is not in
  `wheel` here (#1083), and DHCP goes only to SLiRP's server. A process that
  gains root some other way, a kernel bug for instance, can still flush the
  ruleset. It still cannot leave the VM.
- The layout paragraph at line 237, "its runtime hostname": that line
  becomes "…the template it was created from, `share/` (the only part the
  guest sees, at `/mnt/host`: its runtime hostname, `allow-hosts`, anything
  you put there), and — after the first `run` — `current`…".
- After it, a note:
  > **Upgrading from before #1076.** Guests used to see this whole directory,
  > `current` included. That was a way from a guest to your host, as you or as
  > root. They now see `share/` only. Nothing was moved or deleted: files a
  > guest wrote before, and an `allow-hosts` you wrote, are still one level
  > up, and the guest no longer sees them. Move what it should see into
  > `share/`. An `agent` VM with no allowlist there reaches nothing, which is
  > the safe way to fail. Declarative machines: the same, under
  > `/var/lib/microvms/<name>/share`.
- Lines 272-276: "switches on `microvm.host.enable` upstream … until
  `machines` is non-empty" becomes "…until `machines`, or a `microvm.vms` of
  your own, is non-empty. If you run only imperative `microvm -c` machines,
  set `microvm.host.enable = true` yourself."

**H2: `docs/manual/unattended-installs.md` (P1).**

- Lines 15-26: move the three trailing comments onto their own `#` lines
  above their keys.
- Below the block, add: "`#` starts a comment at the start of a line, or
  after a value. `password`, `luks_passphrase` and `recovery_passphrase` are
  the exception: they are taken exactly as written, `#` and trailing spaces
  included, and one containing a space followed by `#` is refused as a
  probable trailing comment, so a comment never becomes part of a password."

**H3: `installer/AGENTS.md`.**

- In the `## Tests` table, add two rows:
  - `installer-answers` | the answers file's secrets: parsing, argv, cleanup (#1079)
  - `installer-baked-guard` | which system an offline install copies (#1078)
- After the table, add one line: "**Not covered:** an offline free-space or
  offline `--from` install that builds (#1078). That is the `off-free` cell
  of `tests/install-matrix.py`, run by hand; no PR boots it."

**H4: root `AGENTS.md` (`CLAUDE.md` is a symlink to it), the general lesson.** Append to §5's list, at
its end (the one-hour rule):

> - **An EXIT trap reads its variables when the shell exits, not when the trap
>   is set.** `trap 'rm -f "$tmp"' EXIT` inside a function whose `tmp` is
>   `local` removes nothing: by exit the local is gone, and `rm -f ""` succeeds
>   silently. The planned fix for #1079 was written that way. Point the trap at
>   a global, or expand the path when the trap is set.

Do not insert a new section. This is a bullet in §5.

### Baseline, then break proofs

**K1 [C]: format and lint.** Run `nix fmt`, `nix fmt -- --ci`,
`nix run nixpkgs#statix -- check .` and `nix run nixpkgs#deadnix -- --fail .`,
then `git diff --stat`. Report the stat to [O].

**K2 [C]: cheap builds.** With `gh run list` at 0, build each by pinned
`drvPath`, one at a time:

- `installer-answers`
- `installer-baked-guard`
- `installer-from-repo`
- `installer-store-space`
- `installer-failure-hints`
- `installer-network`
- `install-gate`
- `test-registration`
- `grep-q-pipefail`

Then `nix build .#install`, which is shellcheck. Everything must be green.

- If one fails to evaluate, the others in a batch never ran (§13), so build
  them singly.

**K3 [O]: baseline commit.**

- `git add -A`, then check `git status` for any untracked file left out.
- Commit with the subject
  `Close the code review's criticals: guests cannot write what the host runs, and installs format only their own disk (wip)`
  and the Sonnet trailers.
- This is the known-good tree that break proofs restore to (§5).
- *Deviation (implementation):* the push is deferred until after V5. Pushing
  here starts CI, and every break proof and local VM run waits for
  `gh run list` = 0, so an early push would hold them behind the install jobs.
  Each section was committed as it landed, so the baseline is `HEAD` after K2.

**Break proofs [C].** Each follows the same procedure:

1. `cp F F.orig`.
2. Make the break.
3. Prove it landed with `diff F.orig F`, which must be non-empty and show the
   intended lines only.
4. `drv=$(nix eval --raw .#checks.x86_64-linux.<check>.drvPath) && nix build "$drv^*" -L 2>&1 | tee /tmp/claude-1000/break-<n>.log; echo "status ${PIPESTATUS[0]}"`.
   Run it under bash, and record the status from `PIPESTATUS`, not from `tee`.
5. Capture the red lines.
6. `cp F.orig F && rm F.orig`.
7. `git diff --stat F` must be empty against the baseline.
8. Rebuild green.

Check `gh run list` = 0 before each build.

| # | File | Break | Check | Expected red |
|---|---|---|---|---|
| X1 | `installer/install.sh` | delete D1's two `why_not_baked=` lines | `installer-baked-guard` | `FAILED  free-space: wanted built, got baked`, and the same for `from-repo` |
| X2 | `installer/install.sh` | restore C1's hostname loop without the `--from` branch | `installer-from-repo` | `--from: the typed hostname replaced --host alpha (#1077)` |
| X3 | `installer/install.sh` | remove `confirm_repo_disks || exit 1` from `main` | `installer-from-repo` | `main does not run confirm_repo_disks between …` |
| X4 | `installer/install.sh` | `:1457` back to `exit 1` | `installer-store-space` | `partition_free_space calls exit inside the install phases…` |
| X5 | `installer/install.sh` | `partition_free_space \|\| return 1` → `partition_free_space` | `installer-store-space` | `format_disk built the disko script after partition_free_space failed` |
| X6 | `installer/install.sh` | E1 back to `mv "$work" /mnt/etc/nixos` | `installer-store-space` | `install_flake_dir consumed the work tree…` |
| X7 | `installer/install.sh` | F1's secret arm deleted (every value gets `%%#*`) | `installer-answers` | `a1 parsed as: …p` and `mkpasswd stdin was: p` |
| X8 | `installer/install.sh` | `:1167` back to `mkpasswd -m sha-512 "$password"` | `installer-answers` | `the password is in mkpasswd's argv` |
| X9 | `installer/install.sh` | the trap line removed | `installer-answers` | `the fetched answers file survives an exit…` |
| X17 | `installer/install.sh` | F1's `*[[:space:]]\#*` refusal arm deleted | `installer-answers` | `a secret with a trailing comment was accepted (P1 guard)` |
| X10 | `.github/scripts/pr-touches-build.sh` | line 191 back to the old names | `install-gate` | `FAILED  the VM cleanup wrapper does: got 'false', wanted 'true'` |
| X11 | `pkgs/microvm.nix` | `exec_vm` without the `share/` lines | `microvm-template` | `run did not write share/hostname…` |
| X12 | `modules/microvm/guest.nix` | `source = "."` | `microvm-template` | `…hostdir share is not path=share…` |

X13 and X14 (options) and X15 and X16 (VMs) run in V3-V5.

*Deviation (implementation), from the fresh review:*
- **R1:** `pkgs/microvm.nix` removes `share/hostname` before both writes. A guest
  can plant it as a symlink (the 9p share uses `security_model=none`), and
  the host would write through it.
- **R2:** `microvm-template` gains a `canary` case that plants that symlink
  before `run`. Its proof is **X18** (drop `exec_vm`'s `rm`), which went red.
- **R3, R4:** `sandboxes.md` stops overstating the isolation: DHCP also reaches
  the broadcast, `dev` can append to `allow-hosts` (#1100), and a VM that ran
  untrusted code before this change should be recreated.
- **X11** was blind as written: `create_vm` had already written the file, so
  dropping `exec_vm`'s write stayed green. It is re-proven against R2's
  `canary` case.
- **A2, found by X15's green baseline:** `microvm-boot` did not boot. tmpfiles
  runs at sysinit, before upstream's `install-microvm-<name>` creates
  `<state>/<name>`, so it made that directory root-owned and then refused
  `share/` ("unsafe path transition"). The tmpfiles rule now owns both levels,
  `microvm:kvm`, which matches upstream's own `chown`.
- **`microvmProblems` read its own comment:** the `dport 67` rule scanned every
  line of the nftables ruleset, including the `# DHCP ... a bare dport 67`
  comment above the fixed rule, so `checks.options` was red on the untouched
  branch. Comment lines are now skipped. Proven three ways: green with the fix;
  red naming `hyprlandModeAUntouched microvmModeAKeepsHost` with X13 plus the
  Hyprland half of X14; red on the comment with the fix reverted. The combined
  X13/X14 run had also shown that a `microvmProblems` failure exits before the
  `cases` section, so the two are proven in separate runs.

### Local VM and heavy verification (each alone, with CI idle)

**V1 [O]:** check `gh run list` = 0 and that no local VM is running. Tell [C]
to go ahead.

**V2 [C]: `microvm-template` green** (A4). It boots nothing.

**V3 [C]: `microvm-boot`** (P6): `drv=…microvm-boot.drvPath`, then
`nix build "$drv^*" -L`, which is green.

- Break X15: delete A2's tmpfiles block (`cp` procedure).
- The expected red is `microvm@sandbox` failing to start: qemu cannot open
  `path=share`, and `wait_for_unit … timeout=300` fails. Or, if tmpfiles
  created nothing but the unit still started, it fails at
  `test -f …/share/probe-1076`.
- Restore, and rerun green.
- The watch rules:
  - wedge check: `ps -o etime=,%cpu= -p <pid>`;
  - kill only your own pid, never `pkill` by name (§6).

**V4 [C]: `wifi-hwsim`** (F7). Green means nmcli read the piped password.

- Break X16: change F7's `printf '%s\\n' supersecret |` to
  `printf '%s\\n' wrongpassword |`. The red is
  `wait_until_succeeds … timed out` on the handshake count.
- Restore.
- If it is red **without** the break, stop and report to [O], who applies
  F3's fallback (F7) and records it in this plan.

**V5 [C]: `checks.options`, the last local build, alone.** Green, with the
cases `microvmModeAKeepsHost`, `hyprlandModeAUntouched` and
`microvmSshYields` passing, and no `microvmProblems` output. Then two breaks,
each rebuilt alone:

- **X13:** revert B1 to `lib.mkDefault (wanted && svc.machines != { })`.
  Expected red: `these options do not take effect both ways: microvmModeAKeepsHost`.
- **X14:** restore line 235 (`inputs.hyprland.nixosModules.default`) **and**
  B4 to plain `m.sshPort != null`. Expected red: the list names
  `hyprlandModeAUntouched microvmSshYields`.
- A, B3's `microvmProblems` lines: covered by X12 (the same source line) and
  by one options break, **X13b:** B3's `lib.mkForce [ ]` removed. Expected
  red: `a microvm invariant does not hold:` followed by `#1083: the agent
  template's dev is in wheel…`.
  - Run X13b inside the same build as X13, by breaking both files at once.
    One options run then shows both reds, which saves 13 GB and 8 minutes.
  - Name that in the PR.

### Finish

**Z1 [O]: commit the verification state.** If anything changed during the
breaks, `git status` must be clean against K3. Amend the K3 commit:

- drop `(wip)` from the subject;
- the body lists the steps [C] did.

Then push. It is one code commit on top of the artifact commits.

**Z2 [O]: rebase check.** `git fetch origin`. If `main` moved, rebase, read
the status, check `git merge-base origin/main HEAD`, and check that
`git show --stat HEAD` lists only this plan's files (§5, #922).

**Z3 [O]: the agent bus.**

- Read `#nixarchy-agents` again.
- Post P2 (the EXIT trap and locals) and P5 (`nmcli device wifi connect`
  exits 4 with no DHCP, even after a good handshake), unless they are already
  there.
- Redact per §9.

**Z4 [O]: the PR.** Create it with `gh pr create --base main`.

- **Title:** `MicroVM guests can no longer write what the host runs, and the installer formats only the disk it was given`.
  A squash of several commits uses the title and the body (§8).
- **Body,** following the template:
  - **What this changes, and why:** one paragraph per area (A to G).
    - The link lines:
      [intent](intent/2026-09-30-1076-codereview-criticals.md),
      [spec](spec/2026-09-30-1076-codereview-criticals.md),
      [plan](plan/2026-09-30-1076-codereview-criticals.md).
    - `Closes #1076, closes #1077, closes #1078, closes #1079, closes #1082, closes #1083, closes #1084`,
      with the keyword repeated per issue (§8).
    - `Refs #1098` (the `--host` validation only).
  - **Release notes** (verbatim):
    - "MicroVM guests now see `<vm dir>/share` at `/mnt/host`, not the VM's
      whole directory (#1076). Nothing is moved: files a guest wrote before,
      and your `allow-hosts`, stay one level up and are no longer visible to
      it. Move them into `share/`. An `agent` VM with no allowlist there
      reaches nothing."
    - "nixarchy no longer imports the Hyprland flake's NixOS module (#1083).
      A configuration that sets `programs.hyprland.plugins`, `settings`,
      `extraConfig`, `topPrefixes` or `bottomPrefixes` imports
      `inputs.hyprland.nixosModules.default` itself."
    - "`microvm.host.enable` now follows your own `microvm.vms` too. With
      only imperative `microvm -c` machines, set it yourself."
    - "In an answers file, `password`, `luks_passphrase` and
      `recovery_passphrase` are taken exactly as written, `#` included."
  - **How I proved the check fails:** X1-X17 red outputs (X13 and X13b
    together), then the greens.
  - **Checks run locally:** the K2 list, `microvm-template`, `microvm-boot`,
    `wifi-hwsim` and `options`.
  - **The named hole:** offline free-space and offline `--from` (`off-free`
    in `tests/install-matrix.py`) are not run by any PR.
  - **Also say:**
    - `install-encrypted` and `microvm-boot` are nightly-only, and their
      first CI run is the nightly after merge (P9);
    - `.github/scripts/pr-touches-build.sh` is a CI-gate edit (§11), which
      the owner has authorised merging when green;
    - the retargeted `install-gate` cases (P4);
    - the model split: steps A1-A5, B1-B5, C1-C2, D1-D2, E1-E5, F1-F7, G1-G2,
      H1-H4, K1-K2, V2-V5 and X1-X17 by the coder, and everything else by the
      orchestrator.
  - **What this cost:** the §5 EXIT-trap bullet (H4).
  - End the body with the attribution line from the system reminder.

**Z5 [O]: CI.**

- Check `gh pr view <n> --json headRefOid` equals the pushed commit before
  reading any result (§6).
- Expected on the PR: `build` (the generated step runs the new and extended
  runCommand checks), `wifi-hwsim`, `system` and `session`, plus
  install-check's `install`, `free-space` and `installer-refusal`.
- On `cancelled`, read the annotations: eviction versus timeout (§6, §13).
- Never retry until green (§10).

**Z6 [O]: merge.** Merge when every required check is green and
`gh pr view <n> --json mergeable` says `MERGEABLE`.

- Squash, with the PR title as the subject.
- Then confirm that all seven issues closed, and close by hand any that did
  not.

**V6 [O]: the next nightly.** Read `install-encrypted` and `microvm-boot` on
`main`. A red there reopens the matching issue with the log.

**Z7 [O]: announcement.** Post in Discussions, per the owner's rule: the two
behaviour changes users must act on (the share move and the Hyprland module),
with links to the docs changed in H1 and B2.

## Tests

| Check | Layer | Green | Red when |
|---|---|---|---|
| `installer-answers` (new) | runCommand | 6 ok lines | X7, X8, X9, X17 |
| `installer-baked-guard` (new) | runCommand | 3 ok lines | X1 |
| `installer-from-repo` | runCommand | + #1077, #1084 cases | X2, X3 |
| `installer-store-space` | runCommand | + lint, format_disk, generate_hardware_config, install_flake_dir | X4, X5, X6 |
| `install-gate` | runCommand | retargeted cases | X10 |
| `microvm-template` | builds runners, boots nothing | + `path=share`, `share/hostname` | X11, X12 |
| `options` | eval | + 3 cases, + 4 `microvmProblems` lines | X13, X13b, X14 |
| `microvm-boot` | VM, local (nightly in CI) | + share probe | X15 |
| `wifi-hwsim` | VM, local and PR | + piped `--ask` handshake | X16 |
| `installer-failure-hints`, `installer-network`, `test-registration`, `grep-q-pipefail`, `nix build .#install` | runCommand, shellcheck | unchanged green | none |
| `install`, `free-space`, `installer-refusal` | VM, PR CI | green | none planned. They prove the destructive path still installs |
| `install-encrypted` | VM, nightly | green | none planned |
| `off-free` matrix cell | by hand | not run | the named hole |

## Rollback

- **Everything:** `git revert <squash commit>` on `main`. The revert is itself
  a PR. It touches `pr-touches-build.sh`, so the owner merges it.
- **A alone:** revert the `guest.nix`, `microvm.nix` tmpfiles and
  `pkgs/microvm.nix` hunks.
  - The `share/` directories left behind are harmless.
  - Guests then see the whole VM directory again, which is the #1076 hole.
    Say so in that PR.
- **B2 alone:** re-add the import. Keep `/share/hypr` in `pathsToLink`; it
  is then linked twice, which is harmless.
- **B1 and B4:** one-line reverts. `checks.options` then goes red on
  `microvmModeAKeepsHost` and `microvmSshYields`, which is correct: delete
  those cases in the same revert.
- **Installer (C to F):** the functions are independent. Revert per hunk,
  together with its test hunk.
  - F3 has the pre-planned fallback (F7).
  - D's revert re-opens #1078 for offline free-space installs.
- **G:** restoring the old names re-opens #1082. It is a CI-gate change
  either way, so the owner merges it.
- **Nothing here migrates or deletes user data,** so no rollback has
  anything to restore on a machine.
