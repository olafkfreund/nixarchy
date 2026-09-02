# Remote desktop: your running Hyprland session, served over RDP.
#
# Bundled rather than plain for a reason the catalogue's bar does not usually
# meet all at once: nixpkgs has no package (it comes from our overlay), upstream
# ships no systemd unit, the daemon is a client of a compositor that is already
# running, and its password can only be read from inside a config file -- so a
# file has to be rendered at runtime from something safe to commit.
#
# ## The part that decides the shape of this module
#
# hypr-rdp FAILS OPEN. Verified in v0.1.5, src/config.rs:187-197:
#
#     let username = args.username.or(config.username).unwrap_or_default();
#     let password = args.password.or(config.password).unwrap_or_default();
#     if username.is_empty() || password.is_empty() {
#         tracing::warn!("No credentials set (-u/-p). ...");
#         if bind.starts_with("0.0.0.0") { tracing::warn!("... security risk."); }
#     }
#
# `unwrap_or_default()` yields an empty string, not an error. There is no
# `return`, no `bail!`, no exit: it logs two warnings and then serves the
# session. src/server/mod.rs:123 confirms the other end -- credentials are
# built only `if !(username.is_empty() && password.is_empty())`, so with
# neither set there is no authentication at all.
#
# So this module is the only thing between an unrendered secret and an open
# remote desktop, and it refuses in two places rather than one:
#
#   at evaluation   an assertion, when no secret is named or the named secret
#                   is not declared. Nothing builds.
#
#   at runtime      an ExecStartPre that reads the rendered TOML back and exits
#                   non-zero unless it carries a non-empty username AND a
#                   non-empty password. An assertion cannot see a secret that
#                   exists and renders empty, or a template sops-nix failed to
#                   write. A unit that fails loudly is the correct outcome; a
#                   daemon that starts and answers is not.
#
# ## What was checked against the binary rather than assumed
#
#   --config <path>   EXISTS in v0.1.5 (`hypr-rdp --help`), defaulting to
#                     ~/.config/hypr-rdp/config.toml. So the unit points at the
#                     rendered path directly and there is no symlink to manage.
#                     Better still, config.rs:129-137 distinguishes the two:
#                     a MISSING file is tolerated silently when the path is
#                     implicit and is `bail!`ed when it was given explicitly.
#
#   headless          is already the default. `--output` is documented as
#                     "Capture a specific output instead of creating a headless
#                     one" -- so the resizable session a client wants is what
#                     you get by setting nothing, and #156's plan to "default to
#                     the managed headless output" would have been a no-op at
#                     best. `output` here is therefore the opt-OUT, defaulting
#                     to null.
#
#   certificates      src/server/tls.rs generates a self-signed pair into
#                     ~/.config/hypr-rdp/{cert,key}.pem under an flock and
#                     reuses it. Imperative state, but the correct kind:
#                     regenerating per rebuild would churn a fingerprint every
#                     client has pinned. Not managed here; certFile/keyFile are
#                     pass-throughs for someone bringing their own.
inputs:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nixarchy;
  svc = cfg.services.hypr-rdp;

  # The secret is named, declared by the user, and reachable as a placeholder.
  # All three have to hold before the template below can be written at all --
  # `sops.placeholder` is `mapAttrs` over `sops.secrets`, so naming a secret
  # nobody declared is an "attribute missing" error from inside sops-nix rather
  # than anything a reader could act on. The assertions say it in words; this
  # gates the template so they are what the user actually sees.
  secretUsable = svc.passwordSecret != null && config.sops.secrets ? ${svc.passwordSecret};

  configPath = config.sops.templates."hypr-rdp.toml".path;

  # The port to open, taken from `bind` rather than declared twice. Both
  # "0.0.0.0:3389" and "[::]:3389" end in the port, so the last colon-separated
  # field is the answer for either.
  port = lib.toInt (lib.last (lib.splitString ":" svc.bind));

  # The runtime half of the refusal. Reads the rendered file back and requires
  # both fields to be present and non-empty; prints nothing from the file, so a
  # failure never puts the password in the journal.
  guard = pkgs.writeShellApplication {
    name = "nixarchy-hypr-rdp-guard";
    runtimeInputs = [ pkgs.gnugrep ];
    text = ''
      conf="$1"

      if [ ! -r "$conf" ]; then
        echo "hypr-rdp: $conf is missing or unreadable." >&2
        echo "  The sops template did not render. Refusing to start, because" >&2
        echo "  hypr-rdp with no config serves this session unauthenticated." >&2
        exit 1
      fi

      # .+ rather than .* on purpose: `password = ""` is exactly the state
      # upstream turns into an open desktop, and it is what an empty or
      # half-rendered secret produces.
      if ! grep -qE '^username = ".+"$' "$conf"; then
        echo "hypr-rdp: no username in $conf. Refusing to start." >&2
        exit 1
      fi

      if ! grep -qE '^password = ".+"$' "$conf"; then
        echo "hypr-rdp: the password in $conf is empty. Refusing to start." >&2
        echo "  Check that the sops secret named by" >&2
        echo "  programs.nixarchy.services.hypr-rdp.passwordSecret has a value." >&2
        exit 1
      fi
    '';
  };
in
{
  options.programs.nixarchy.services.hypr-rdp = {
    enable = lib.mkEnableOption ''
      hypr-rdp, serving the Hyprland session you are already logged into over
      RDP.

      This shares a running desktop; it is not remote login. Nobody is logged
      in for you, and with no session there is nothing to connect to. Nothing
      listens beyond localhost until you change `bind`, and the firewall stays
      closed until you say otherwise -- the reachable-from-elsewhere path this
      expects is your tailnet, which needs no firewall change at all.

      Requires a sops secret for the password. Enabling this without one fails
      the rebuild rather than starting a desktop anyone can connect to
    '';

    package = lib.mkOption {
      type = lib.types.package;
      default = (pkgs.extend inputs.self.overlays.default).hypr-rdp;
      defaultText = lib.literalExpression "(pkgs.extend nixarchy.overlays.default).hypr-rdp";
      description = ''
        The hypr-rdp build to run. From nixarchy's overlay because nixpkgs has
        no such package; when it gains one, this default becomes the ordinary
        `pkgs.hypr-rdp` and nothing else here changes.

        Lazy, so a machine that never enables this never builds it -- being in
        the overlay is not being on the system.
      '';
    };

    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = cfg.user;
      defaultText = lib.literalExpression "config.programs.nixarchy.user";
      description = ''
        Whose session is served, and who owns the rendered config file. The
        daemon runs as this user because it talks to their compositor; it
        cannot serve a session belonging to somebody else.
      '';
    };

    username = lib.mkOption {
      type = lib.types.str;
      default = "nixarchy";
      description = ''
        The name an RDP client logs in with. Not the Linux account -- that is
        `user` above, and this one is checked by hypr-rdp itself against the
        password below, so it can be anything.

        It is deliberately not the login name by default: a name a client
        already knows is half of a guess.
      '';
    };

    passwordSecret = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "hypr-rdp-password";
      description = ''
        Name of the sops secret holding the RDP password -- the attribute name
        under `sops.secrets`, not the password and not a path to it.

        Required, and the requirement is not a formality. hypr-rdp reads its
        password from an inline string in its config file or from `-p` on the
        command line, and given neither it logs a warning and then serves the
        session with no authentication at all. So this module renders the file
        with the secret in it, and refuses to build or to start without one.

        The value must not contain a double quote, a backslash or a newline:
        it is written into a TOML string, and a password that breaks the
        quoting makes hypr-rdp fail to parse its config. That failure is safe
        -- it exits rather than starting -- but it is a confusing way to find
        out.
      '';
    };

    bind = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:3389";
      example = "0.0.0.0:3389";
      description = ''
        Address and port to listen on. Upstream's own default, which reaches
        only this machine.

        The shape worth wanting is `0.0.0.0:3389` with `openFirewall = false`
        and `programs.nixarchy.services.tailscale.trustInterface` on: the
        daemon listens on every interface, the firewall refuses everything
        arriving on the LAN, and the tailnet is trusted -- so your own machines
        can reach it and the coffee shop cannot.
      '';
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open the port from `bind` to the whole local network.

        Off, and its own decision rather than a consequence of `bind`, because
        it is the expensive one: RDP on a routable port is a login prompt
        facing every device on that network, guessed at as fast as they like,
        by nothing that rate-limits them. Reach it over your tailnet instead
        and leave this alone.
      '';
    };

    output = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "DP-1";
      description = ''
        Mirror an existing monitor instead of creating a headless one.

        Null gives you the headless output, which is what you usually want:
        the session resizes to the client's window, and it does not go away
        when a monitor is switched off or unplugged. Naming a real output
        mirrors that screen at its resolution, which is what you want only
        when somebody is sitting in front of it.
      '';
    };

    certFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        TLS certificate to serve, if you have one. Left null, hypr-rdp
        generates a self-signed pair into `~/.config/hypr-rdp/` on first start
        and reuses it afterwards -- imperative, and deliberately not managed
        here: a certificate regenerated on every rebuild changes the
        fingerprint every client has pinned, so each connection would ask
        again whether this machine is the one you meant.
      '';
    };

    keyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        The private key for `certFile`. hypr-rdp refuses to start given one
        without the other (src/server/tls.rs), so set both or neither.
      '';
    };
  };

  config = lib.mkIf (cfg.enable && svc.enable) (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = svc.user != null;
            message = ''
              programs.nixarchy.services.hypr-rdp is enabled but no user is set,
              and there is no session to serve without one.

              Set programs.nixarchy.user, which is what this follows, or set
              programs.nixarchy.services.hypr-rdp.user directly.
            '';
          }
          {
            assertion = svc.passwordSecret != null;
            message = ''
              programs.nixarchy.services.hypr-rdp is enabled with no
              passwordSecret, and hypr-rdp with no password does not refuse to
              start -- it logs a warning and serves your desktop to anyone who
              connects. So this stops the rebuild instead.

              Encrypt a password for this host:

                # 1. this host's public key, as an age recipient
                nix-shell -p ssh-to-age --run \
                  'ssh-keyscan localhost 2>/dev/null | ssh-to-age'

                # 2. add it under `keys:` in .sops.yaml, and name it in the
                #    creation rule for hosts/<name>/secrets.yaml

                # 3. write the password into the encrypted file
                sops edit hosts/<name>/secrets.yaml

              Then declare it and point this option at it:

                sops.secrets.hypr-rdp-password.sopsFile = ./secrets.yaml;
                programs.nixarchy.services.hypr-rdp.passwordSecret =
                  "hypr-rdp-password";

              Step 1 needs an SSH host key, which exists only where
              services.openssh.enable is true -- sops-nix has no other key
              source on a nixarchy machine and will say so itself. That is the
              same fail-closed shape as this assertion, one layer down.
            '';
          }
          {
            assertion = svc.passwordSecret == null || config.sops.secrets ? ${svc.passwordSecret};
            message = ''
              programs.nixarchy.services.hypr-rdp.passwordSecret names
              "${toString svc.passwordSecret}", but no such secret is declared.

              The name is an attribute under sops.secrets, not a file and not
              the password. Declare it:

                sops.secrets."${toString svc.passwordSecret}".sopsFile =
                  ./secrets.yaml;

              Without this the config file would render with the placeholder
              text where the password belongs, or not at all.
            '';
          }
          {
            assertion = (svc.certFile == null) == (svc.keyFile == null);
            message = ''
              programs.nixarchy.services.hypr-rdp has one of certFile/keyFile
              and not the other. hypr-rdp bails on that pair rather than
              falling back to a generated certificate, so the unit would fail
              at every start. Set both, or neither and let it generate one.
            '';
          }
        ];
      }

      (lib.mkIf secretUsable {
        # The password goes INSIDE this file, because that is the only place
        # hypr-rdp will read it from that is not a command line -- and
        # /proc/*/cmdline is world-readable, so `-p` would publish it to every
        # process on the machine. 0400 and owned by the user whose session it
        # is; the rendered path is under /run, never the store and never git.
        sops.templates."hypr-rdp.toml" = {
          owner = svc.user;
          mode = "0400";
          # Plain assignment, not mkDefault. `content` is types.lines, which
          # merges -- and a mkDefault on a merging type is dropped BEFORE the
          # merge, so ours would vanish the moment anyone added a line of their
          # own. The rule is the header of modules/services/default.nix.
          #
          # restartUnits is deliberately not set: sops-nix restarts SYSTEM
          # units and this is a user unit, so it could only name something that
          # does not exist. After changing the password in the encrypted file,
          # `systemctl --user restart hypr-rdp` is the step.
          content = lib.concatStringsSep "\n" (
            [
              ''bind = "${svc.bind}"''
              ''username = "${svc.username}"''
              ''password = "${config.sops.placeholder.${svc.passwordSecret}}"''
            ]
            ++ lib.optional (svc.output != null) ''output = "${svc.output}"''
            ++ lib.optional (svc.certFile != null) ''cert = "${svc.certFile}"''
            ++ lib.optional (svc.keyFile != null) ''key = "${svc.keyFile}"''
            ++ [ "" ]
          );
        };

        systemd.user.services.hypr-rdp = {
          description = "Serve this Hyprland session over RDP";

          # A client of the compositor: it cannot precede the session and must
          # not outlive it. wayland-session-waitenv is uwsm's -- it is what puts
          # HYPRLAND_INSTANCE_SIGNATURE and WAYLAND_DISPLAY into the user
          # manager's environment, and hypr-rdp resolves the compositor through
          # both. Lists, so plain assignment.
          after = [
            "graphical-session.target"
            "wayland-session-waitenv.service"
          ];
          partOf = [ "graphical-session.target" ];
          wantedBy = [ "graphical-session.target" ];

          unitConfig = {
            # systemd.user.services is declared for every user on the machine,
            # and the rendered config is 0400 to one of them. Without this, any
            # other user logging in graphically gets a unit that starts, cannot
            # read the file and fails -- noise about a service they did not ask
            # for. ConditionUser skips it for them instead.
            ConditionUser = svc.user;
            # After= is ordering only, as omarchy-fcitx5 records: an `omarchy
            # update` over SSH has a live user manager and no compositor.
            # WAYLAND_DISPLAY is what actually proves a graphical session.
            ConditionEnvironment = "WAYLAND_DISPLAY";
          };

          serviceConfig = {
            Type = "simple";

            # The runtime refusal. Upstream will not do it: given an empty
            # password it warns and serves. This exits non-zero and systemd
            # never reaches ExecStart.
            ExecStartPre = "${guard}/bin/nixarchy-hypr-rdp-guard ${configPath}";

            # --config, not a symlink into ~/.config/hypr-rdp: the flag exists
            # in v0.1.5, and naming the path explicitly also turns a missing
            # file from "silently use defaults" into a hard error (config.rs
            # distinguishes the implicit and explicit cases). The certificates
            # still land in ~/.config/hypr-rdp, which is upstream's and stays
            # writable.
            ExecStart = "${svc.package}/bin/hypr-rdp --config ${configPath}";

            Restart = "on-failure";
            # If the guard is the thing failing, nothing here will fix itself,
            # and systemd's default start-rate limit stops the loop after five
            # attempts and leaves the unit failed -- which is the loud state
            # this whole module is arranged to reach.
            RestartSec = 5;
          };
        };
      })

      # A list, so plain assignment: mkDefault would drop this entirely the
      # moment the user opens a port of their own.
      (lib.mkIf svc.openFirewall {
        networking.firewall.allowedTCPPorts = [ port ];
      })
    ]
  );
}
