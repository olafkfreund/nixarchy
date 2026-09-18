---
status: draft
issue: 763
intent: intent/2026-09-18-763-microvm-templates.md
---
# Spec: k3s, agent-claude and node templates, and 4 GiB for podman

## Decisions taken from the intent's open questions

All five taken as proposed, with one mechanism the intent could not know:

1. **Agents.** `codex` and `opencode` are built into `agent-claude`.
   `claude-code` is added only when the evaluation allows unfree, through a
   `builtins.tryEval` probe (flake.nix:392-406's pattern), never through
   `pkgs.config.allowUnfree` -- see fact 2 for why that flag is the wrong test.
2. **Allowlist default.** `api.anthropic.com`, `api.openai.com`, `github.com`,
   `codeload.github.com` are allowed without being listed. They come from a
   file inside the closure (`/etc/nixarchy-agent/allow-hosts`), so no
   per-VM `allow-hosts` file can remove them. The per-VM file still adds.
3. **k3s.** 4 GiB, 2 vCPU, a 20 GiB `/var/lib/rancher` volume, traefik and
   servicelb disabled, kubectl inside the guest only. No host API port in v1.
4. **podman.** `microvm.mem = 4096`.
5. **Name.** `agent-claude`.

How "the host allows unfree" reaches a runner, which the intent leaves open:

- The permanent path (`modules/services/microvm.nix:213`) evaluates the
  template inside the user's own system. microvm.nix passes the host's `pkgs`
  into the guest evaluation (`nixos-modules/host/options.nix:78,101-104` in the
  pinned commit), so the user's `nixpkgs.config.allowUnfree = true` reaches
  the probe and claude-code goes in. Nothing to add.
- The disposable path (`pkgs/microvm.nix:237`) runs
  `nix build github:olafkfreund/nixarchy/<rev>#microvm-agent-claude`: a pure
  evaluation of a flake with no `nixpkgs.config` (`flake.nix:1505-1519`). The
  user's system config cannot reach it. The one route nixpkgs itself offers is
  `NIXPKGS_ALLOW_UNFREE=1` plus `--impure` (`check-meta.nix:77`). So
  `nixarchy vm run` passes `--impure` exactly when `NIXPKGS_ALLOW_UNFREE` is
  set (one word in `pkgs/microvm.nix`). Without it the public runner is built;
  with it a runner that carries claude-code is built locally and never touches
  CI, which never sets the variable.

## Facts checked for this spec

1. **Packages on the pinned nixpkgs** (`0968519e`), by
   `nix eval --json --impure --expr` over `import <nixpkgs> { config = {}; }`:
   `codex` 0.154.0 Apache-2.0, `opencode` 1.18.30 MIT, `claude-code` 2.1.272
   unfree (`meta.mainProgram = claude`), `nodejs` 24.20.0 (= `nodejs_24`, the
   active LTS), `pnpm` 11.27.0, `k3s` 1.35.8+k3s1. All but claude-code
   evaluate with unfree off.
2. **`pkgs.config.allowUnfree` is the wrong guard.** With
   `NIXPKGS_ALLOW_UNFREE=1 nix eval --impure`, `pkgs.config.allowUnfree` is
   `false` and `(builtins.tryEval pkgs.claude-code.outPath).success` is
   `true`; with the variable unset the probe is `false`; without `--impure`
   the variable is ignored. `check-meta.nix:77`:
   `allowUnfree = config.allowUnfree || getEnv "NIXPKGS_ALLOW_UNFREE" == "1"`.
3. **The probe works through mkMicrovm's module stack.** A nixosSystem built
   from `inputs.microvm.nixosModules.microvm`, `modules/microvm/guest.nix`,
   `modules/microvm/templates/agent.nix` and the systemPackages line from
   section 3 below, evaluated with `nix eval --impure --file`: with
   `NIXPKGS_ALLOW_UNFREE` unset `environment.systemPackages` has no
   `claude-code` and `declaredRunner` still evaluates; with it set, it does.
4. **k3s generates its own token.** `services.k3s.token` defaults to `""`
   and `--token` is passed only when it is non-empty
   (`nixos/modules/services/cluster/rancher/default.nix:429-438,935`); the
   only assertion requiring a token is for `role = "agent"` (`:831`). The
   generated token lands under `/var/lib/rancher/k3s/server/`, on the volume.
5. **k3s module shape.** `services.k3s.disable` is `listOf str` mapped to
   `--disable=<x>` (`default.nix:491,940`); `extraFlags` is `either str
   (listOf str)` (`:467`); the module adds `k3s` to `systemPackages` (`:838`)
   and sets no kernel modules or sysctls. The k3s package symlinks
   `bin/kubectl` to `k3s` (`pkgs/applications/networking/cluster/k3s/builder.nix:348`),
   so no separate `pkgs.kubectl`.
6. **Guest kernel.** microvm.nix uses `config.boot.kernelPackages.kernel`
   (`nixos-modules/microvm/options.nix:90-93`), i.e. the full NixOS kernel
   with its modules tree; `overlay` and `br_netfilter` are modules k3s
   modprobes itself. The owner's hand-kept flake
   (`~/.config/nixos/hosts/p620/microvm/flake.nix`) sets no kernel modules
   and runs, so none are set here.
7. **microvm.nix defaults**: `mem = 512`, `vcpu = 1`
   (`nixos-modules/microvm/options.nix:104-113`). podman.nix sets neither.
8. **Cache cost.** Every new package is served by cache.nixos.org
   (`nix path-info -S --store https://cache.nixos.org`): k3s 602 MiB, codex
   561 MiB, nodejs 255 MiB, pnpm 249 MiB, opencode 226 MiB. cache-budget.sh
   subtracts upstream-served paths (`.github/scripts/cache-budget.sh:7-8,47-61`),
   so they cost the nixarchy cache nothing. What a runner costs there is its
   nixarchy-built paths: about 30 MiB per KVM runner and 29 MiB per -tcg
   runner (spec/2026-09-15-697-cache-allowlist.md:19-34). Six runners add
   about 180 MiB to 697's 1.05 GB estimate, inside the 2048 MiB per-commit
   budget. The local `microvm-shell` runner closure is 1.58 GiB
   (`nix path-info -S .#microvm-shell`), nearly all from cache.nixos.org.
9. **Where a new template has to be registered.** `cache-allowlist.sh:46-52`
   and `flake.nix:1116-1145` read the catalogue, so the runners and their
   pushes come for free. `tests/microvm-template.nix:35-38` has a hand table
   `volumeImages`, and `:206-213` fails when `docs/manual/sandboxes.md` has no
   `| \`<name>\` |` row. The agent assertions at `:215-323` are hard-wired
   to `templates.agent`.
10. **CI never passes `--impure`** to a runner build: `build.yml:1275` and
    `:1284` go through `build-unless-proven.sh` and `cache-allowlist.sh`
    with plain `nix build`. `microvm-boot` is nightly-only (`build.yml:370`)
    and boots the `shell` template (`tests/microvm-boot.nix:74-75`).

## Design

### 1. `modules/microvm/templates/agent.nix` -- a second allowlist source

The oneshot reads two files instead of one. The first is inside the closure
and may not exist; the second is the per-VM file it reads today.

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
          # (existing comment on anchoring and dot escaping stays)
          printf '^(.*\.)?%s$\n' "$(printf '%s' "$host" | sed 's/\./\\./g')" >> ${filterFile}
        done < "$src"
      done
      chmod 0444 ${filterFile}
    '';
```

Nothing else in the file changes. `environment.etc` is plain NixOS, so the
catalogue's bar holds and `agent` stays behaviourally identical.

### 2. `modules/microvm/templates/agent-claude.nix` -- new

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

`microvm.mem` stays agent.nix's 2560: the agents are clients, and a checkout
plus a language server was the sizing already done there.

### 3. `modules/microvm/templates/k3s.nix` -- new

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

### 4. `modules/microvm/templates/node.nix` -- new

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

### 5. `modules/microvm/templates/podman.nix` -- memory

Appended inside the attribute set, after `microvm.volumes`:

```nix
  # microvm.nix's default is 512 MiB (nixos-modules/microvm/options.nix), and
  # guest.nix does not raise it. An image pull decompresses layers in memory
  # and a build runs whatever the Dockerfile runs; 4 GiB is what stops
  # either from being the thing that kills a VM whose point is containers.
  microvm.mem = 4096;
```

### 6. `data/microvm-templates.nix` -- three entries

Inserted after `podman` (node), after `agent` (agent-claude), and after
`persistent` (k3s):

```nix
  node = {
    label = "Node";
    module = ../modules/microvm/templates/node.nix;
    note = "nodejs (LTS) and pnpm, 3 GiB of RAM. Ephemeral like Shell -- run 'pnpm install' inside /mnt/host if node_modules should outlive the VM.";
  };

  # Agent, with the agents. The unfree one is the reason the note has a
  # second sentence: what you get depends on whether the evaluation that
  # built the runner allowed it.
  agent-claude = {
    label = "Agent (Claude)";
    module = ../modules/microvm/templates/agent-claude.nix;
    note = "Agent's egress fence with codex and opencode preinstalled, and api.anthropic.com, api.openai.com, github.com and codeload.github.com allowed without listing them; 'allow-hosts' adds to that. claude-code is included only when unfree is allowed -- NIXPKGS_ALLOW_UNFREE=1 before 'nixarchy vm run', or allowUnfree on a permanent machine -- and is never served by the public cache.";
  };

  k3s = {
    label = "k3s";
    module = ../modules/microvm/templates/k3s.nix;
    note = "A single-node k3s server, 4 GiB of RAM and 2 vCPUs. /var/lib/rancher is a 20 GiB volume that survives a restart, so the cluster and its token do; traefik and servicelb are off, and the API is reachable only from inside the guest ('kubectl get nodes' at the console).";
  };
```

### 7. `pkgs/microvm.nix` -- `--impure` when the user asks for unfree

Both `nix build` calls in `run_vm` (`:237` and `:244`) gain
`${NIXPKGS_ALLOW_UNFREE:+--impure}` after `build`, with the comment:

```sh
          # A pure `nix build github:...` cannot see this system's
          # allowUnfree, and nixpkgs' own override for that case
          # (NIXPKGS_ALLOW_UNFREE=1) is read by getEnv, which pure
          # evaluation returns empty. So the variable buys --impure, and
          # nothing else does: the runner then differs from the public one
          # by exactly the unfree packages a template probes for
          # (modules/microvm/templates/agent-claude.nix), and is built here.
```

Nothing else in the CLI changes. The stub-`nix` half of
`checks.microvm-template` (`tests/microvm-template.nix:325-`) already
records argv; no new assertion is needed for a flag CI cannot exercise.

### 8. `tests/microvm-template.nix` -- three small edits

- `volumeImages` gains `k3s = "var-lib-rancher.img";` (`:35-38`), so the
  relative-path assertion covers the new volume.
- The agent block (`:215-323`) is wrapped in
  `lib.concatMapStrings (name: lib.optionalString (lib.hasPrefix "agent" name) '' ... '') names`
  with `templates.agent.kvm` becoming `templates.${name}.kvm` and the
  `agent:` message prefixes becoming `${name}:`. Every existing assertion
  holds for agent-claude unchanged: same units, same filter file, same
  ruleset, same uid.
- After that block, for agent-claude only:

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

### 9. `docs/manual/sandboxes.md` -- three rows

After the `persistent` row of the table at `:64-70`:

```
| `node` | `nodejs` (LTS), `pnpm`, 3 GiB RAM | ephemeral — `pnpm install` inside `/mnt/host` if `node_modules` should outlive the VM |
| `agent-claude` | `agent` plus codex and opencode, with the model endpoints and GitHub pre-allowed | `claude-code` only when unfree is allowed — `NIXPKGS_ALLOW_UNFREE=1 nixarchy vm run <name>`, or `allowUnfree` on a permanent machine; never in the public cache |
| `k3s` | single-node k3s server, 4 GiB RAM, 2 vCPU | `/var/lib/rancher` is a 20 GiB volume, so the cluster and its generated token survive a restart; traefik and servicelb off; `kubectl` inside the guest only |
```

No change to `docs/internals/flake.md`: its runner section is per-entry and
generic. No change to `flake.nix`, `.github/`, or `modules/services/microvm.nix`:
all read the catalogue.

## Alternatives rejected

- **Guard claude-code on `pkgs.config.allowUnfree`.** False under the only
  route the disposable path has (fact 2); it would make the env-var route
  build a runner without claude-code while claiming to honour unfree.
- **`nixpkgs.config.allowUnfree = true` inside the template.** Would put
  claude-code into the runner CI builds and pushes. Redistribution.
- **A `coding-agent` name with free agents only.** Loses the Claude case the
  issue asks for; the probe gives both without a second template.
- **Defaults appended with `lib.mkAfter` on the oneshot's `script`.** Lands
  after the `chmod 0444` and duplicates the regex escaping. Two sources in
  one loop is shorter and keeps the escaping in one place.
- **A nixarchy option for the default hosts.** The bar says no nixarchy
  vocabulary in a template. `environment.etc` is the plain-NixOS spelling.
- **`pkgs.kubectl` in k3s.** The k3s package already symlinks `kubectl`
  (fact 5); adding nixpkgs' would only put a second, `priority`-losing copy on
  PATH and 62 MiB in the closure.
- **`trustedInterfaces = [ "cni0" "flannel.1" ]` instead of firewall off.**
  Depends on interface names this spec did not verify on this k3s version;
  the hand-kept flake's choice is proven and inbound is already closed by
  SLiRP.
- **Forwarding 6443 to the host in v1.** Only the permanent path can
  (`modules/services/microvm.nix:225-231`), and it already can through
  `modules`; nothing template-side is needed.
- **2 GiB for podman.** A single `buildah`/`podman build` of a Node or Rust
  image exceeds it; 4 GiB is what the intent's owner approved.
- **A dedicated boot check per template.** `microvm-boot` is nightly and
  boots one template (fact 10); three more nested-TCG boots would triple it.
  Boot is manual per template (Verification).

## Risks

- **`--impure` widens evaluation.** Under `--impure`, `builtins.getEnv` and
  `currentSystem` are readable during the flake evaluation. Nothing in the
  flake reads either on the runner path, and the variable is only set by a
  user who typed it. Scoped to the two `nix build` lines.
- **The locally built unfree runner is rebuilt every `run`.** `run_vm`
  re-runs `nix build --out-link` each time (`pkgs/microvm.nix:237`); with the
  variable unset next time, the public runner replaces it. That is the
  designed behaviour, and the note says the variable goes before `run`.
- **Agents that need more than four hosts.** opencode fetches a provider
  list from models.dev at start; Claude Code sends telemetry to hosts not
  listed. Both are refused by the proxy, which is the template's contract;
  whether either tool degrades gracefully is not verified here. `allow-hosts`
  is the answer either way, and the manual smoke below is where it is found.
- **Proxy honouring.** codex (reqwest), Claude Code (Node) and opencode (Bun)
  all read `HTTPS_PROXY`; that is documented for each but not exercised
  here. A tool that ignores it gets no network at all -- fail closed, as on
  `agent`.
- **k3s under SLiRP.** The node IP is 10.0.2.15 and flannel's vxlan has one
  peer, itself. Single-node works with this shape in the hand-kept flake
  (on tap); not yet booted on SLiRP. Smoke test covers it.
- **Closure growth.** k3s's runner is about 2.2 GiB in the store on the host
  (1.58 GiB shell plus 602 MiB k3s); a user's first `nixarchy vm run` of it
  downloads that from cache.nixos.org. Same for codex (561 MiB). Not a
  nixarchy-cache cost (fact 8), but a disk one; the notes say the memory,
  not the download, which is the existing convention.
- **`claude` at a console with no browser.** OAuth login cannot complete in
  the guest; `ANTHROPIC_API_KEY` is the route, and the template header says
  so. Same for codex.

## Verification

Checks, from the worktree:

```sh
nix build .#checks.x86_64-linux.microvm-template --print-build-logs
nix build .#checks.x86_64-linux.microvm-boot --print-build-logs   # nightly's; runs where /dev/kvm exists
.github/scripts/cache-allowlist.sh runners                          # lists 16 entries, six new
.github/scripts/cache-budget.sh                                     # stays under 2048 MiB
```

Every runner builds, both ways:

```sh
for t in k3s agent-claude node podman; do
  nix build --no-link --print-out-paths .#microvm-$t .#microvm-$t-tcg
done
```

The public agent-claude runner has no claude-code, and the catalogue
evaluates with unfree off (both pure, the way CI and `nixarchy vm run` build):

```sh
env -u NIXPKGS_ALLOW_UNFREE nix eval --raw \
  '.#packages.x86_64-linux.microvm-agent-claude' --apply 'r: r.name'
sys=$(readlink -f "$(nix build --no-link --print-out-paths .#microvm-agent-claude)/share/microvm/system")
test ! -e "$sys/sw/bin/claude" && test -e "$sys/sw/bin/codex" && test -e "$sys/sw/bin/opencode"
grep -x api.anthropic.com "$sys/etc/nixarchy-agent/allow-hosts"
nix eval --json --expr 'builtins.attrNames (import ./data/microvm-templates.nix)' --impure
```

And the local unfree runner does carry it, and is a different derivation:

```sh
NIXPKGS_ALLOW_UNFREE=1 nix build --impure --no-link --print-out-paths .#microvm-agent-claude
# prints a different store path; its share/microvm/system/sw/bin/claude exists
```

Memory and volumes, read off the runners the way the check does:

```sh
grep -o -- '-m [0-9]*' result-podman/bin/microvm-run   # -m 4096
grep -o -- '-m [0-9]*\|-smp [0-9]*' result-k3s/bin/microvm-run   # -m 4096, -smp 2
grep -o 'file=var-lib-rancher.img' result-k3s/bin/microvm-run
```

Manual smoke, on a KVM host, one VM per template (`nixarchy vm templates`
first, to see the three new rows):

```sh
nixarchy vm create n1 --template node && nixarchy vm run n1
#   node --version; pnpm --version; free -m shows ~3 GiB

nixarchy vm create p1 --template podman && nixarchy vm run p1
#   free -m shows ~4 GiB; podman pull docker.io/library/alpine succeeds

nixarchy vm create k1 --template k3s && nixarchy vm run k1
#   kubectl get nodes           -> one node, Ready (allow ~60 s after login)
#   sudo cat /var/lib/rancher/k3s/server/token   -> a generated token
#   nixarchy vm stop k1; nixarchy vm run k1; kubectl get nodes -> same node, Ready
#   ls ~/.local/state/nixarchy/microvm/k1/  on the host -> var-lib-rancher.img

nixarchy vm create a1 --template agent-claude && nixarchy vm run a1
#   codex --version; opencode --version; which claude -> not found
#   curl -sI https://api.anthropic.com   -> an HTTP status (proxy allowed it, no allow-hosts file)
#   curl -sI https://example.com         -> 403 from tinyproxy
#   printf 'example.com\n' > ~/.local/state/nixarchy/microvm/a1/allow-hosts on the host,
#   restart the VM: curl -sI https://example.com -> 200; api.anthropic.com still allowed
#   printf '\0\0garbage((\n' > .../allow-hosts, restart: api.anthropic.com still allowed
nixarchy vm stop a1
NIXPKGS_ALLOW_UNFREE=1 nixarchy vm run a1
#   which claude -> /run/current-system/sw/bin/claude
```

Permanent path, in a scratch host config (not deployed):

```nix
programs.nixarchy.services.microvm.machines.k.template = "k3s";
programs.nixarchy.services.microvm.machines.a.template = "agent-claude";
```

with `nixpkgs.config.allowUnfree = true`: `nix eval` of that host's
`config.microvm.vms.a.config.config.environment.systemPackages` names
`claude-code`; with it false, it does not, and evaluation still succeeds.
