# The `agent` template. Every other template in this catalogue answers "give
# me a machine"; this one answers "give me a machine that cannot phone
# anywhere I did not name".
#
# The filesystem half of sandboxing an AI agent was already done and is the
# strong half: modules/microvm/guest.nix boots a guest whose only view of the
# host is the read-only /nix/store and one directory at /mnt/host (the VM's
# `share/`, never the directory holding its runner, #1076). That is a
# kernel boundary, and it is why a MicroVM beats the bubblewrap wrappers
# (`agent-sandbox.nix`, `nixwrap`) that map the host user into the sandbox and
# so leave ~/.ssh one escape away.
#
# The network was the half still missing. `shell`, `python` and `podman` all
# inherit guest.nix's SLiRP interface, which is "NAT out, nothing in" -- fine
# for a package fetch, and no constraint at all on a process you are running
# precisely because you do not fully trust what it will do. An agent that can
# reach only its model endpoint and your git remote is a materially different
# risk from one that can reach anything.
#
# ## How the egress restriction actually works
#
# Two pieces, and neither is nixarchy vocabulary -- both are plain NixOS, per
# data/microvm-templates.nix's bar:
#
#   1. `networking.nftables` with an OUTPUT chain whose policy is `drop`. The
#      only uid allowed off the machine is tinyproxy's. Not the `dev` user,
#      not root, not DNS: an agent running as `dev` has no socket to the
#      outside world at all, so there is no direct connection to make and no
#      DNS channel to tunnel out of.
#   2. `services.tinyproxy` on 127.0.0.1:8888 with `FilterDefaultDeny`, which
#      is what turns "tinyproxy may egress" back into "only these hosts may".
#      It filters the host in a CONNECT line, so HTTPS is allowed or refused
#      by name without anything terminating the TLS.
#
# `environment.variables` then points http_proxy/https_proxy at it, which is
# the interface curl, git-over-https, pip, uv, npm and every model SDK already
# speak. Nothing in the guest has to know a proxy exists.
#
# ## The allowlist is per-VM, and so cannot be in the closure
#
# The hosts one person allows are not the hosts the next person allows, and
# data/microvm-templates.nix's first rule is that nothing in a template may
# depend on a per-VM value -- one closure serves every VM of a template. So
# the allowlist arrives exactly the way the hostname does in
# modules/microvm/guest.nix: a plain-text file the caller drops in the VM's
# host-managed `policy/` sibling of `share/`, read at boot from a read-only
# /mnt/agent-policy share by a oneshot
# that runs inside the VM that actually has it mounted.
#
# `/mnt/agent-policy/allow-hosts`, one hostname per line, `#` comments allowed. No
# file, or an empty one, means an empty filter -- which under
# `FilterDefaultDeny` is deny-everything, the only safe way for this to fail.
# A template that imports this one may also ship a closure-side list at
# `/etc/nixarchy-agent/allow-hosts` (agent-claude does), read first and
# beyond the reach of anything in the VM's directory; this template ships none.
{ lib, pkgs, ... }:
let
  proxy = "http://127.0.0.1:8888";

  # A fixed uid rather than the dynamic one the tinyproxy module would
  # otherwise allocate, because `networking.nftables.checkRuleset` runs
  # `nft --check` in the build sandbox, where /etc/passwd has no `tinyproxy`
  # line and `meta skuid tinyproxy` therefore fails to parse. Numeric here is
  # the same rule nixpkgs' own `preCheckRuleset` example exists to work
  # around, without the workaround.
  proxyUid = 399;

  filterFile = "/run/nixarchy-agent/allow.filter";
in
{
  microvm.shares = [
    {
      tag = "agent-policy";
      source = "policy";
      mountPoint = "/mnt/agent-policy";
      proto = "9p";
      readOnly = true;
    }
  ];
  fileSystems."/mnt/agent-policy".options = [ "ro" ];

  environment.systemPackages = [
    pkgs.git
    pkgs.curl
  ];

  services = {
    tinyproxy = {
      enable = true;
      settings = {
        Listen = "127.0.0.1";
        Port = 8888;
        Allow = "127.0.0.1";
        Timeout = 600;
        # Filter is typed `nullOr path` upstream, and this string is an
        # absolute path that is deliberately NOT a Nix path literal: a path
        # literal would be copied into the store at build time, and the whole
        # point is that this file is written at boot from the per-VM share.
        Filter = filterFile;
        # The line that makes this an allowlist rather than a blocklist. Without
        # it a filter file matches hosts to REFUSE and everything else goes
        # through, which is the opposite of what this template promises.
        FilterDefaultDeny = true;
        FilterExtended = true;
        FilterCaseSensitive = false;
        # CONNECT to 443 and nothing else. Without this, an allowed hostname is
        # a tunnel to any port on that host, ssh included.
        ConnectPort = 443;
        LogLevel = "Connect";
      };
    };

    # See the comment above networking.nameservers for why both are off.
    resolved.enable = false;
    nscd.enable = false;
  };

  users.users.tinyproxy.uid = proxyUid;

  # No wheel (#1083): `sudo nft flush ruleset` would undo the whole filter.
  # mkForce because guest.nix's list merges; agent-claude imports this file.
  users.users.dev.extraGroups = lib.mkForce [ ];

  systemd.services.nixarchy-agent-allowlist = {
    description = "Build this guest's egress allowlist from the host policy share";
    wantedBy = [ "multi-user.target" ];
    # Ordered and required, both: tinyproxy reads its filter file once, at
    # start, so a tinyproxy that came up first would be running an allowlist
    # that no longer describes this VM.
    before = [ "tinyproxy.service" ];
    requiredBy = [ "tinyproxy.service" ];
    unitConfig.RequiresMountsFor = [ "/mnt/agent-policy" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    # Truncate first, unconditionally. A leftover filter from a previous boot
    # is impossible on a tmpfs root, but an early `exit` on a missing
    # allow-hosts would leave tinyproxy pointed at a file that does not exist
    # -- and tinyproxy treats an unreadable filter as no filter, which under
    # FilterDefaultDeny is not obviously fail-closed. An empty file is.
    script = ''
      install -d -m 0755 /run/nixarchy-agent
      : > ${filterFile}
      # Two sources, closure first. /etc/nixarchy-agent/allow-hosts is
      # written by a template that imports this one (agent-claude) and so
      # cannot be edited, emptied or deleted from the VM's directory:
      # whatever it names is allowed on every VM of that template, and
      # /mnt/agent-policy/allow-hosts only ever adds. This template writes no such
      # file, so for `agent` the behaviour is unchanged.
      for src in /etc/nixarchy-agent/allow-hosts /mnt/agent-policy/allow-hosts; do
        if [ -L "$src" ]; then
          echo "allow-hosts: refusing symlink $src" >&2
          exit 1
        fi
        [ -e "$src" ] || continue
        content=$(${pkgs.coreutils}/bin/cat "$src") || {
          echo "allow-hosts: cannot read $src" >&2
          exit 1
        }
        while IFS= read -r host; do
          case "$host" in
            "" | \#*) continue ;;
            # Not a hostname, not a filter line. tinyproxy compiles every
            # line as a regex and refuses to start on a bad one -- which is
            # fail-closed, and also takes the closure-side defaults down
            # with a single typo in the per-VM file. Skipped, and said so
            # in the journal.
            *[!A-Za-z0-9.-]*)
              echo "allow-hosts: skipping '$host' from $src: not a hostname" >&2
              continue
              ;;
          esac
          # Anchored, with the dots escaped and one optional subdomain label
          # group: `github.com` allows api.github.com and refuses
          # notgithub.com. An unescaped dot would make `.` match any
          # character, which is how an allowlist silently becomes wider than
          # it reads.
          printf '^(.*\.)?%s$\n' "$(printf '%s' "$host" | sed 's/\./\\./g')" >> ${filterFile}
        done <<< "$content"
      done
      if [ -e /mnt/host/allow-hosts ]; then
        echo "allow-hosts: ignoring legacy /mnt/host/allow-hosts; copy reviewed entries to <vm dir>/policy/allow-hosts on the host" >&2
      fi
      chmod 0444 ${filterFile}
    '';
  };

  # The one thing the guest's own processes have to be told. Both spellings:
  # curl and git read the lowercase ones, a good deal of Python and Node reads
  # the uppercase ones, and a tool that reads neither simply gets no network
  # rather than an unfiltered one.
  environment.variables = {
    http_proxy = proxy;
    https_proxy = proxy;
    HTTP_PROXY = proxy;
    HTTPS_PROXY = proxy;
    no_proxy = "localhost,127.0.0.1";
    NO_PROXY = "localhost,127.0.0.1";
  };

  # Name resolution has to happen INSIDE tinyproxy's process, or the ruleset
  # below drops it. microvm.nix's optimization module turns on networkd, and
  # nixpkgs' networkd module then defaults systemd-resolved on, which puts
  # `resolve` first in nsswitch's hosts line: every lookup, the proxy's
  # included, is made by resolved's uid and refused at 53/udp -- measured as
  # "Could not retrieve address info ... Temporary failure in name
  # resolution" from tinyproxy on every CONNECT, on the `agent` runner main
  # shipped. nscd is the same hole one step later (nsncd resolves as `nscd`),
  # and NixOS requires the NSS module list to be empty when nscd is off. With
  # both gone glibc resolves in the calling process: tinyproxy's lookups
  # leave under its own uid, and anything else's are dropped, which is what
  # the ruleset promised all along. 10.0.2.3 is SLiRP's own DNS forwarder,
  # the same on every VM of every template that keeps guest.nix's user
  # interface -- without resolved nothing else writes a nameserver.
  system.nssModules = lib.mkForce [ ];
  networking.nameservers = [ "10.0.2.3" ];

  networking.nftables = {
    enable = true;
    # Only an output chain. Inbound is already answered twice over -- SLiRP
    # user networking has nothing to forward in, and networking.firewall's own
    # `inet nixos-fw` table is still here -- and a second input base chain
    # would only make the ruleset harder to read for no gain.
    ruleset = ''
      table inet nixarchy-agent {
        chain output {
          type filter hook output priority filter; policy drop;

          ct state established,related accept
          oifname "lo" accept

          # DHCP, to SLiRP's server only (#1083): a bare `dport 67` let any uid
          # send to any address on 67. 255.255.255.255 for the renewals that
          # broadcast; the first DISCOVER leaves on a packet socket nft never sees.
          udp sport 68 udp dport 67 ip daddr { 10.0.2.2, 255.255.255.255 } accept

          # The proxy, and nothing else on this machine, may resolve a name
          # or open a connection. Dropping DNS for every other uid is not
          # incidental -- a 53/udp socket is an exfiltration channel that
          # needs no allowed host at all.
          meta skuid ${toString proxyUid} udp dport 53 accept
          meta skuid ${toString proxyUid} tcp dport 53 accept
          meta skuid ${toString proxyUid} tcp dport { 80, 443 } accept
        }
      }
    '';
  };

  # Enough for an agent, a checkout and a language server. Above the 512 MiB
  # microvm.nix default for the same reason modules/microvm/templates/python.nix
  # raises it, and below that template's 3072 because nothing here resolves a
  # dependency-heavy lockfile.
  microvm.mem = 2560;
}
