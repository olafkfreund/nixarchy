---
status: approved
issue: 763
spec: spec/2026-09-18-763-microvm-templates.md
---
# Plan: k3s, agent-claude and node templates, and 4 GiB for podman

Closes #763.

## Approved decisions (self-contained summary)

Three new entries in `data/microvm-templates.nix`, one memory fix, and the
smallest plumbing that lets an unfree package reach one of them without ever
reaching the public cache.

- **`podman`** gets `microvm.mem = 4096`. Today it runs on microvm.nix's 512
  MiB default (`nixos-modules/microvm/options.nix:110` in the pinned commit);
  `modules/microvm/guest.nix` raises nothing.
- **`node`**: `pkgs.nodejs` (nixpkgs' default, 24.20.0 on the pinned
  nixpkgs = active LTS) and `pkgs.pnpm`, `microvm.mem = 3072`, same shape as
  `python`.
- **`k3s`**: `services.k3s` server, `disable = [ "traefik" "servicelb" ]`,
  `--write-kubeconfig-mode=644`, `KUBECONFIG=/etc/rancher/k3s/k3s.yaml`,
  firewall off, `/var/lib/rancher` on a 20 GiB relative-path volume
  (`var-lib-rancher.img`), 4096 MiB, 2 vCPU. **No token**: `services.k3s.token`
  defaults to `""` and `--token` is only passed when set
  (`nixos/modules/services/cluster/rancher/default.nix:429-438,935`); a server
  given none generates its own under `/var/lib/rancher/k3s/server/`, on the
  volume. `kubectl` is the k3s package's own symlink (`builder.nix:348`); no
  `pkgs.kubectl`. No kernel modules: the guest kernel is the full NixOS one and
  k3s modprobes `overlay`/`br_netfilter` itself. kubectl inside the guest only
  in v1; no host API port.
- **`agent-claude`**: imports `agent.nix`; `codex` (Apache-2.0) and `opencode`
  (MIT) unconditional; `claude-code` (unfree) added via
  `lib.optional (builtins.tryEval pkgs.claude-code.outPath).success` — the
  probe pattern flake.nix:392-406 already uses. **Not**
  `pkgs.config.allowUnfree`: measured, that flag stays `false` under the
  `NIXPKGS_ALLOW_UNFREE=1 --impure` route while the probe is `true`
  (`check-meta.nix:77` reads the env var itself). Memory stays agent's 2560.
- **Default hosts** `api.anthropic.com`, `api.openai.com`, `github.com`,
  `codeload.github.com` live in the closure as
  `environment.etc."nixarchy-agent/allow-hosts"`. `agent.nix`'s allowlist
  oneshot reads that file first, then `/mnt/host/allow-hosts`, in one loop
  with the same escaping. A broken or empty per-VM file cannot remove them.
  `agent` writes no such file and is unchanged in behaviour.
- **How unfree reaches a runner.** Permanent path
  (`modules/services/microvm.nix:213`): microvm.nix evaluates the guest with
  the host's own `pkgs` (`nixos-modules/host/options.nix:78,101-104`), so the
  user's `allowUnfree` reaches the probe; nothing to add. Disposable path
  (`pkgs/microvm.nix:237,244`): `nix build github:olafkfreund/nixarchy/<rev>#…`
  is pure and sees no host config; the only route nixpkgs offers is
  `NIXPKGS_ALLOW_UNFREE=1` plus `--impure`. So both `nix build` lines gain
  `${NIXPKGS_ALLOW_UNFREE:+--impure}`. CI never sets the variable, so the
  public runner never contains claude-code; the local one is a different
  derivation.
- **Checks**: `tests/microvm-template.nix` gets `volumeImages.k3s`, the agent
  block looped over every `agent*` template, and an agent-claude block
  asserting the four default hosts, `codex`/`opencode` present and
  `sw/bin/claude` absent from the CI-built runner. No new boot check:
  `microvm-boot` is nightly-only and boots `shell`; three more nested-TCG
  boots would triple it. Boot is smoked by hand per template.
- **Docs**: three rows in `docs/manual/sandboxes.md`'s template table (the
  check at `tests/microvm-template.nix:206-213` fails without them). Nothing in
  `flake.nix`, `.github/`, `cache-allowlist.sh`, `modules/services/microvm.nix`
  or `docs/internals/flake.md`: all read the catalogue.
- **Cache**: every new package is on cache.nixos.org (k3s 602 MiB, codex 561,
  nodejs 255, pnpm 249, opencode 226 — `nix path-info -S --store
  https://cache.nixos.org`), and `cache-budget.sh` subtracts upstream-served
  paths, so six runners add only their nixarchy-built paths: ~30 MiB per KVM
  and ~29 MiB per -tcg runner (spec/2026-09-15-697-cache-allowlist.md:19-34),
  ~180 MiB on 697's 1.05 GB, inside the 2048 MiB per-commit budget.

Rejected, so an implementer does not reintroduce them: `nixpkgs.config.allowUnfree`
inside the template (pushes unfree to the cache); a `coding-agent` free-only
name; `lib.mkAfter` on the oneshot's `script` (lands after `chmod 0444`,
duplicates escaping); a nixarchy option for default hosts (the catalogue's bar
is plain NixOS); `pkgs.kubectl`; `trustedInterfaces = [ "cni0" "flannel.1" ]`
(interface names unverified; firewall off is the hand-kept flake's proven
choice); forwarding 6443 in v1; 2 GiB for podman.

## Steps

Conventions. One step, one commit. Subjects are full sentences ending in
`(#763)` — `git log --oneline -10` for the register, no conventional-commits
prefix (AGENTS.md §8). Edit `.nix` through Bash, not the Edit tool (the local
`PostToolUse:Edit` formatter rewrites unrelated lines). Every commit message
ends with:

```
Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JfJ93KQHG48bi61gbRUwod
```

Store paths below are the pinned inputs' — `nix eval --raw --impure --expr
'(builtins.getFlake (toString ./.)).inputs.nixpkgs.outPath'` resolves them.

1. **`modules/microvm/templates/podman.nix`** — append inside the set, after
   `microvm.volumes`:

   ```nix
     # microvm.nix's default is 512 MiB (nixos-modules/microvm/options.nix), and
     # guest.nix does not raise it. An image pull decompresses layers in memory
     # and a build runs whatever the Dockerfile runs; 4 GiB is what stops
     # either from being the thing that kills a VM whose point is containers.
     microvm.mem = 4096;
   ```

   Commit: `The podman template gets 4 GiB, because 512 MiB is not a container host (#763)`
   → verify: `nix build .#microvm-podman -o result-podman && grep -o -- '-m [0-9]*' result-podman/bin/microvm-run` prints `-m 4096`.

2. **`modules/microvm/templates/node.nix`** — new file:

   ```nix
   # The `node` template: python.nix's JavaScript counterpart, and nothing more.
   # `nodejs` is nixpkgs' default, which tracks the active LTS line; `pnpm`
   # because it is what a lockfile-heavy install wants. Same memory as python
   # for the same reason: resolving a dependency tree on a share as slow as 9p
   # is the expensive part.
   #
   # node_modules written into the guest's tmpfs root are gone at the next
   # boot; `pnpm install` inside /mnt/host writes them onto the host directory
   # `nixarchy vm run` shares in, which is what makes them outlive the VM.
   { pkgs, ... }:
   {
     environment.systemPackages = [
       pkgs.nodejs
       pkgs.pnpm
     ];

     microvm.mem = 3072;
   }
   ```

   **`data/microvm-templates.nix`** — after the `podman` entry:

   ```nix
     node = {
       label = "Node";
       module = ../modules/microvm/templates/node.nix;
       note = "nodejs (LTS) and pnpm, 3 GiB of RAM. Ephemeral like Shell -- run 'pnpm install' inside /mnt/host if node_modules should outlive the VM.";
     };
   ```

   **`docs/manual/sandboxes.md`** — after the `persistent` row (`:70`):

   ```
   | `node` | `nodejs` (LTS), `pnpm`, 3 GiB RAM | ephemeral — `pnpm install` inside `/mnt/host` if `node_modules` should outlive the VM |
   ```

   The row goes in the same commit as the entry: `checks.microvm-template`
   fails on a catalogue name with no row (`tests/microvm-template.nix:206-213`),
   and a commit that does not build its own checks is not one step.

   Commit: `A node template, so python has a JavaScript counterpart (#763)`
   → verify: `nix build .#microvm-node .#microvm-node-tcg`; `sys=$(readlink -f result/share/microvm/system); test -e $sys/sw/bin/node && test -e $sys/sw/bin/pnpm`; `grep -o -- '-m [0-9]*' result/bin/microvm-run` → `-m 3072`.

3. **`modules/microvm/templates/k3s.nix`** — new file:

   ```nix
   # The `k3s` template: a single-node Kubernetes that survives a restart.
   #
   # `/var/lib/rancher` is the volume -- a RELATIVE image path, podman.nix's
   # rule -- and it is what makes this a cluster rather than a demo: the
   # datastore, the images containerd pulled, the CA and the node token k3s
   # generated on first boot all live under it. No token is written here:
   # services.k3s passes --token only when one is set, and a server given none
   # generates its own into that directory. That is the whole answer to "no
   # secret in a template".
   #
   # traefik and servicelb are off, as in the flake this replaces. Both exist
   # to expose Services outward, and nothing outward exists: guest.nix's SLiRP
   # interface forwards nothing in, so kubectl inside the guest is the API in
   # v1 (a permanent machine's forwarded ports are how that changes).
   #
   # The firewall is off for the same reason the owner's hand-kept flake turned
   # it off: SLiRP already answers inbound, and nixos-fw only ever stood between
   # pods on cni0 and the node's own services.
   { ... }:
   {
     services.k3s = {
       enable = true;
       role = "server";
       disable = [
         "traefik"
         "servicelb"
       ];
       # The kubeconfig k3s writes is root-only by default; `dev` is who sits at
       # the console. 644 is fine on a guest with one user and no network in.
       extraFlags = [ "--write-kubeconfig-mode=644" ];
     };

     # `kubectl` is the k3s package's own symlink (it is on PATH via
     # services.k3s); this is the one thing it needs to be told.
     environment.variables.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";

     networking.firewall.enable = false;

     microvm.volumes = [
       {
         image = "var-lib-rancher.img";
         mountPoint = "/var/lib/rancher";
         size = 20 * 1024;
         fsType = "ext4";
         autoCreate = true;
       }
     ];

     # The control plane alone idles near 1 GiB; 4 GiB leaves room for
     # workloads, and a second vCPU is the difference between a scheduler that
     # keeps up and one that does not.
     microvm.mem = 4096;
     microvm.vcpu = 2;
   }
   ```

   **`data/microvm-templates.nix`** — after the `persistent` entry:

   ```nix
     k3s = {
       label = "k3s";
       module = ../modules/microvm/templates/k3s.nix;
       note = "A single-node k3s server, 4 GiB of RAM and 2 vCPUs. /var/lib/rancher is a 20 GiB volume that survives a restart, so the cluster and its token do; traefik and servicelb are off, and the API is reachable only from inside the guest ('kubectl get nodes' at the console).";
     };
   ```

   **`tests/microvm-template.nix:35-38`** — `volumeImages` gains
   `k3s = "var-lib-rancher.img";`.

   **`docs/manual/sandboxes.md`** — row after `node`:

   ```
   | `k3s` | single-node k3s server, 4 GiB RAM, 2 vCPU | `/var/lib/rancher` is a 20 GiB volume, so the cluster and its generated token survive a restart; traefik and servicelb off; `kubectl` inside the guest only |
   ```

   Commit: `A k3s template: one node, a volume for the cluster, and no token in the closure (#763)`
   → verify: `nix build .#microvm-k3s -o result-k3s .#microvm-k3s-tcg`;
   `grep -oE -- '-m [0-9]+|-smp [0-9]+|file=var-lib-rancher.img' result-k3s/bin/microvm-run` prints `-m 4096`, `-smp 2`, `file=var-lib-rancher.img`;
   `grep -c 'token' $(readlink -f result-k3s/share/microvm/system)/etc/systemd/system/k3s.service` is 0 (no `--token`);
   `grep -- '--disable=traefik' …/k3s.service` and `--disable=servicelb` both hit.

4. **`modules/microvm/templates/agent.nix`** — the oneshot's `script`
   (`:116-133`) becomes:

   ```nix
       script = ''
         install -d -m 0755 /run/nixarchy-agent
         : > ${filterFile}
         # Two sources, closure first. /etc/nixarchy-agent/allow-hosts is
         # written by a template that imports this one (agent-claude) and so
         # cannot be edited, emptied or deleted from the VM's directory:
         # whatever it names is allowed on every VM of that template, and
         # /mnt/host/allow-hosts only ever adds. This template writes no such
         # file, so for `agent` the behaviour is unchanged.
         for src in /etc/nixarchy-agent/allow-hosts /mnt/host/allow-hosts; do
           [ -r "$src" ] || continue
           while read -r host; do
             case "$host" in
               "" | \#*) continue ;;
             esac
             # Anchored, with the dots escaped and one optional subdomain label
             # group: `github.com` allows api.github.com and refuses
             # notgithub.com. An unescaped dot would make `.` match any
             # character, which is how an allowlist silently becomes wider than
             # it reads.
             printf '^(.*\.)?%s$\n' "$(printf '%s' "$host" | sed 's/\./\\./g')" >> ${filterFile}
           done < "$src"
         done
         chmod 0444 ${filterFile}
       '';
   ```

   Keep the existing comment above `script` about truncating first. Nothing
   else in the file changes. The header's "## The allowlist is per-VM" section
   gains one sentence: a template importing this one may also ship a
   closure-side list at `/etc/nixarchy-agent/allow-hosts`, read first.

   Commit: `The agent allowlist can also come from the closure, for a template that ships agents (#763)`
   → verify, that `agent` is unchanged. Before and after the edit:
   ```sh
   sys=$(readlink -f "$(nix build --no-link --print-out-paths .#microvm-agent)/share/microvm/system")
   test ! -e "$sys/etc/nixarchy-agent/allow-hosts"                       # agent ships no closure list
   script=$(grep -oE '/nix/store/[^ ]*unit-script-nixarchy-agent-allowlist-start[^ ]*' \
             "$sys/etc/systemd/system/nixarchy-agent-allowlist.service" | head -1)
   cat "$script"   # save both copies; `diff` them: the loop is the only change
   ```
   Then `nix build .#checks.x86_64-linux.microvm-template` — every existing
   agent assertion (units, `FilterDefaultDeny`, uid, `Filter` path) passes.

5. **`modules/microvm/templates/agent-claude.nix`** — new file:

   ```nix
   # The `agent-claude` template: `agent`'s fence, with the agents already
   # inside it. `agent` ships no agent, and installing one into a root
   # filesystem that is thrown away every boot, through a proxy that refuses
   # every host you have not listed, is the wrong first experience.
   #
   # ## Who is in, and why claude-code is conditional
   #
   # codex (Apache-2.0) and opencode (MIT) are unconditional. claude-code is
   # unfree: nixarchy must not push it to its public cache, and a catalogue that
   # threw without allowUnfree would break `nixarchy vm templates` for everyone.
   # So it is probed with tryEval, the same way flake.nix probes unfree apps for
   # the doctor. The probe is `false` in CI and in `nixarchy vm run`'s pure
   # `nix build github:...`, so the public runner never contains it. It is
   # `true` on the permanent path (modules/services/microvm.nix evaluates this
   # module with the host's own pkgs, allowUnfree included) and under
   # `NIXPKGS_ALLOW_UNFREE=1 nixarchy vm run`, which adds --impure -- that
   # runner is built locally and differs from the public one by exactly this
   # package. Not `pkgs.config.allowUnfree`: that is false under the env-var
   # route (check-meta.nix reads the variable itself), so it would miss the
   # only route the disposable path has.
   #
   # ## What is allowed without asking
   #
   # /etc/nixarchy-agent/allow-hosts is the closure-side half of agent.nix's
   # allowlist: read before /mnt/host/allow-hosts, and not deletable from the
   # VM's directory. The two model endpoints and GitHub over HTTPS, and nothing
   # a package manager needs -- `allow-hosts` still says what else this VM may
   # reach, exactly as on `agent`. API keys are yours to set in the guest
   # (ANTHROPIC_API_KEY, OPENAI_API_KEY); nothing here can know them.
   { pkgs, lib, ... }:
   {
     imports = [ ./agent.nix ];

     environment.systemPackages = [
       pkgs.codex
       pkgs.opencode
     ]
     ++ lib.optional (builtins.tryEval pkgs.claude-code.outPath).success pkgs.claude-code;

     environment.etc."nixarchy-agent/allow-hosts".text = ''
       api.anthropic.com
       api.openai.com
       github.com
       codeload.github.com
     '';
   }
   ```

   **`data/microvm-templates.nix`** — after the `agent` entry:

   ```nix
     # Agent, with the agents. The unfree one is the reason the note has a
     # second sentence: what you get depends on whether the evaluation that
     # built the runner allowed it.
     agent-claude = {
       label = "Agent (Claude)";
       module = ../modules/microvm/templates/agent-claude.nix;
       note = "Agent's egress fence with codex and opencode preinstalled, and api.anthropic.com, api.openai.com, github.com and codeload.github.com allowed without listing them; 'allow-hosts' adds to that. claude-code is included only when unfree is allowed -- NIXPKGS_ALLOW_UNFREE=1 before 'nixarchy vm run', or allowUnfree on a permanent machine -- and is never served by the public cache.";
     };
   ```

   **`docs/manual/sandboxes.md`** — row between `node` and `k3s`:

   ```
   | `agent-claude` | `agent` plus codex and opencode, with the model endpoints and GitHub pre-allowed | `claude-code` only when unfree is allowed — `NIXPKGS_ALLOW_UNFREE=1 nixarchy vm run <name>`, or `allowUnfree` on a permanent machine; never in the public cache |
   ```

   Commit: `An agent-claude template: agent's fence with codex, opencode and, where unfree is allowed, claude (#763)`
   → verify, unfree off (what CI and `nixarchy vm run` build):
   `env -u NIXPKGS_ALLOW_UNFREE nix build --no-link --print-out-paths .#microvm-agent-claude`;
   `sys=$(readlink -f <that>/share/microvm/system)`;
   `test ! -e $sys/sw/bin/claude && test -e $sys/sw/bin/codex && test -e $sys/sw/bin/opencode`;
   `grep -cx -e api.anthropic.com -e api.openai.com -e github.com -e codeload.github.com $sys/etc/nixarchy-agent/allow-hosts` → 4.
   Unfree on: `NIXPKGS_ALLOW_UNFREE=1 nix build --impure --no-link --print-out-paths .#microvm-agent-claude`
   prints a *different* path whose `share/microvm/system/sw/bin/claude` exists.
   Catalogue: `nix eval --impure --json --expr 'builtins.attrNames (import ./data/microvm-templates.nix)'` lists eight names.

6. **`pkgs/microvm.nix`** — both `nix build` lines in `run_vm` (`:237` and
   `:244`) become `nix build ''${NIXPKGS_ALLOW_UNFREE:+--impure} "$flakeUrl#$attr" --out-link "$dir/current"`
   (and `"$fallbackUrl#$attr"`), with this comment above the first:

   ```sh
             # A pure `nix build github:...` cannot see this system's
             # allowUnfree, and nixpkgs' own override for that case
             # (NIXPKGS_ALLOW_UNFREE=1) is read by getEnv, which pure
             # evaluation returns empty. So the variable buys --impure, and
             # nothing else does: the runner then differs from the public one
             # by exactly the unfree packages a template probes for
             # (modules/microvm/templates/agent-claude.nix), and is built here.
   ```

   Note the `''${` escape: the script is inside a Nix `''` string. Nothing
   else in the CLI changes. **#762 overlap**: #762 rewrites `run_vm` (adds
   `--detach`, `console`, `set-template`, `--json`). This step touches two
   lines of that function; whichever lands second rebases onto the other, and
   #762's `run --detach` must keep the same `${NIXPKGS_ALLOW_UNFREE:+--impure}`
   on its build line — say so in the PR body so #762's author sees it.

   Commit: `nixarchy vm run passes --impure when NIXPKGS_ALLOW_UNFREE asks for it, so an unfree runner can be built locally (#763)`
   → verify: `nix build .#nixarchy-vm && grep -c 'NIXPKGS_ALLOW_UNFREE:+--impure' result/bin/nixarchy-vm` → 2;
   `nix build .#checks.x86_64-linux.microvm-template` (its stub-`nix` half
   still sees `build … --out-link`, since the flag is empty when unset).

7. **`tests/microvm-template.nix`** — two edits to the agent block
   (`:215-323`) and one new block after it.

   - Wrap the block: `${lib.optionalString (templates ? agent) ''` →
     `${lib.concatMapStrings (name: lib.optionalString (lib.hasPrefix "agent" name) ''`
     … `'') names}`. Inside, `${templates.agent.kvm}` → `${templates.${name}.kvm}`
     and every `echo "agent: …"` → `echo "${name}: …"`; the `== the agent
     template …` banner → `== ${name}: cannot reach what it was not allowed ==`.
     Every existing assertion holds for agent-claude: same units, same
     `Filter` path, same ruleset, same uid.
   - New block, after it:

   ```nix
       ${lib.optionalString (templates ? agent-claude) ''
         echo "== agent-claude: default hosts in the closure, nothing unfree in it =="
         sys=$(readlink -f ${templates.agent-claude.kvm}/share/microvm/system)
         for host in api.anthropic.com api.openai.com github.com codeload.github.com; do
           if ! grep -qx "$host" "$sys/etc/nixarchy-agent/allow-hosts"; then
             echo "agent-claude: $host is not in the closure-side allowlist" >&2
             fail=1
           fi
         done
         for bin in codex opencode; do
           if [ ! -e "$sys/sw/bin/$bin" ]; then
             echo "agent-claude: $bin is not on the guest's PATH" >&2
             fail=1
           fi
         done
         # CI is a pure evaluation, so this is the public runner. A `claude`
         # here means an unfree package is about to be pushed to a public cache.
         if [ -e "$sys/sw/bin/claude" ]; then
           echo "agent-claude: claude-code is in the runner CI builds -- it must never reach the public cache" >&2
           fail=1
         fi
       ''}
   ```

   Commit: `checks.microvm-template reads every agent template, and refuses a public runner that carries claude (#763)`
   → verify: `nix build .#checks.x86_64-linux.microvm-template --print-build-logs`
   shows both `agent:` and `agent-claude:` banners. Then Tests §2 (watch it fail).

8. **Format and lint.** `nix fmt -- --ci`, `statix check .`, `deadnix --fail .`.
   Fold into step 7's commit if only whitespace moves; otherwise
   `The new templates are formatted the way the tree is (#763)`.
   → verify: all three clean.

9. **PR.** Title: `Three MicroVM templates -- k3s, agent-claude and node -- and enough memory for podman (#763)`.
   Body links `intent/`, `spec/`, this plan; pastes Tests §2's failing output;
   names the #762 overlap (step 6); says the unfree runner is never built by
   CI and why (pure evaluation). `Closes #763`. Ends with the attribution
   lines from the session reminder.
   → verify: `build.yml`'s `microvm-template` step and `cache-budget` step
   green; `.github/scripts/cache-allowlist.sh runners` lists 16 entries.

## Tests

1. **The checks.**
   ```sh
   nix build .#checks.x86_64-linux.microvm-template --print-build-logs
   nix build .#checks.x86_64-linux.microvm-boot --print-build-logs   # nightly's; needs /dev/kvm on L1
   .github/scripts/cache-allowlist.sh runners | wc -l                # 16
   CACHE_BUDGET_MIB=2048 .github/scripts/cache-budget.sh              # ~1.2 GB; a number near 2048 means something new is not on cache.nixos.org
   for t in shell python podman agent persistent node agent-claude k3s; do
     nix build --no-link .#microvm-$t .#microvm-$t-tcg || exit 1
   done
   ```

2. **Watch it fail** (AGENTS.md §1), in one tree, restore after each:
   - Delete `codeload.github.com` from agent-claude.nix's etc file → the
     `agent-claude:` host loop goes red.
   - Change k3s.nix's image to `/var/lib/nixarchy/var-lib-rancher.img` → the
     absolute-path assertion goes red.
   - Temporarily `nixpkgs.config.allowUnfree = true;` in agent-claude.nix →
     the `sw/bin/claude` assertion goes red. This is the one to paste into the PR.
   `git diff --stat` before believing the red.

3. **Unfree off and on, evaluated** (the two runners must be different derivations):
   ```sh
   env -u NIXPKGS_ALLOW_UNFREE nix build --no-link --print-out-paths .#microvm-agent-claude
   NIXPKGS_ALLOW_UNFREE=1 nix build --impure --no-link --print-out-paths .#microvm-agent-claude
   ```
   Two paths; only the second's `share/microvm/system/sw/bin/claude` exists.

4. **Manual smoke, on a KVM host, with the branch's runner.** `nixarchy vm run`
   builds `github:olafkfreund/nixarchy/<installed rev>`, not this checkout, so
   the branch is smoked by dropping its runner where `run_vm` would put it and
   exec'ing it from the VM's directory the way `run_vm` does
   (`pkgs/microvm.nix:247-249`):
   ```sh
   smoke() {  # smoke <name> <template>
     nixarchy vm create "$1" --template "$2"
     dir=${XDG_STATE_HOME:-$HOME/.local/state}/nixarchy/microvm/$1
     nix build ".#microvm-$2" --out-link "$dir/current"
     echo "$1" > "$dir/hostname"
     (cd "$dir" && exec ./current/bin/microvm-run)
   }
   ```
   `nixarchy vm create` validates the template against the *installed*
   catalogue, so on a machine whose nixarchy predates this branch, create the
   directory by hand instead: `mkdir -p "$dir" && echo "$2" > "$dir/template"`.
   Stop with `(cd "$dir" && ./current/bin/microvm-shutdown)`; remove with
   `nixarchy vm rm`.

   - `smoke n1 node`: `node --version` (v24), `pnpm --version`, `free -m` ≈ 3 GiB.
   - `smoke p1 podman`: `free -m` ≈ 4 GiB; `podman pull docker.io/library/alpine` succeeds.
   - `smoke k1 k3s`: after ~60 s, `kubectl get nodes` → one node `Ready`;
     `sudo cat /var/lib/rancher/k3s/server/token` → a generated token.
     Shut down, start again: `kubectl get nodes` → same node, `Ready`;
     `ls $dir` on the host shows `var-lib-rancher.img`.
   - `smoke a1 agent-claude` (no `allow-hosts` file):
     `codex --version`, `opencode --version`, `which claude` → not found;
     `curl -sI https://api.anthropic.com` → an HTTP status line;
     `curl -sI https://example.com` → tinyproxy's 403.
     Then on the host `printf 'example.com\n' > $dir/allow-hosts`, restart:
     `example.com` → 200, `api.anthropic.com` still allowed.
     Then `printf '\0\0garbage((\n' > $dir/allow-hosts`, restart:
     `api.anthropic.com` still allowed.
     Then `NIXPKGS_ALLOW_UNFREE=1 nix build --impure .#microvm-agent-claude --out-link $dir/current`,
     restart: `which claude` → `/run/current-system/sw/bin/claude`.

5. **Permanent path, evaluated (not deployed)**, in a scratch flake importing
   `nixosModules.nixarchy` with
   `programs.nixarchy.services.microvm.machines.a.template = "agent-claude";`:
   with `nixpkgs.config.allowUnfree = true`,
   `nix eval .#nixosConfigurations.<h>.config.microvm.vms.a.config.config.environment.systemPackages --apply 'ps: map (p: p.pname) ps'`
   names `claude-code`; with it false it does not, and evaluation succeeds.

6. `nix fmt -- --ci`, `statix check .`, `deadnix --fail .`.

Not attempted: a per-template boot check. `microvm-boot` is nightly, boots
one template under nested TCG, and three more would triple it; step 4 is the
boot proof and says so.

## Rollback

- **podman OOMs or won't start with 4 GiB on a small host** → revert step 1
  alone; nothing depends on it.
- **k3s does not come up under SLiRP** → revert step 3 (module, entry,
  `volumeImages` line, doc row). No other step imports it. A VM directory
  keeps its `var-lib-rancher.img` until `nixarchy vm rm`.
- **The agent.nix loop breaks `agent`** → revert step 4 *and* step 5 together
  (agent-claude's default hosts depend on the loop). `checks.microvm-template`
  is what says whether `agent` broke, before this ships.
- **`--impure` misbehaves in `nixarchy vm run`** → revert step 6 alone. The
  template still builds; only the local-unfree route is gone, and the
  permanent path is unaffected. **#762**: if #762 has landed first, the revert
  is two lines in its rewritten `run_vm`, not a `git revert`.
- **Whole change** → revert the squash commit. Nothing is stateful on the
  host except VM directories users made from the new templates, which
  `nixarchy vm rm` removes; nothing reaches the cache that was not built
  purely, so there is nothing to evict.

## Implementation record

### Deviations

(none yet)

### Test results

(none yet)
