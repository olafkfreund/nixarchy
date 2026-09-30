{ pkgs }:
let
  inherit (pkgs) lib;
  eval =
    settings:
    (lib.evalModules {
      modules = [
        ../modules/services/syncthing.nix
        ../modules/services/open-webui.nix
        ../modules/flatpaks.nix
        {
          options = {
            programs.nixarchy.enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
            };
            programs.nixarchy.user = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
            };
            users.users = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.submodule {
                  options = {
                    home = lib.mkOption {
                      type = lib.types.str;
                      default = "/var/empty";
                    };
                    isNormalUser = lib.mkOption {
                      type = lib.types.bool;
                      default = false;
                    };
                  };
                }
              );
              default = { };
            };
            services = {
              syncthing = {
                enable = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                };
                user = lib.mkOption {
                  type = lib.types.str;
                  default = "syncthing";
                };
                dataDir = lib.mkOption {
                  type = lib.types.str;
                  default = "/var/lib/syncthing";
                };
                configDir = lib.mkOption {
                  type = lib.types.str;
                  default = "/var/lib/syncthing/.config";
                };
                overrideFolders = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                };
                overrideDevices = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                };
              };
              ollama = {
                enable = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                };
                host = lib.mkOption {
                  type = lib.types.str;
                  default = "127.0.0.1";
                };
                port = lib.mkOption {
                  type = lib.types.int;
                  default = 11434;
                };
              };
              open-webui = {
                enable = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                };
                openFirewall = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                };
                port = lib.mkOption {
                  type = lib.types.int;
                  default = 8080;
                };
                environment = lib.mkOption {
                  type = lib.types.attrsOf lib.types.str;
                  default = { };
                };
              };
              flatpak = {
                enable = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                };
                remotes = lib.mkOption {
                  type = lib.types.listOf lib.types.anything;
                  default = [ ];
                };
                packages = lib.mkOption {
                  type = lib.types.listOf lib.types.anything;
                  default = [ ];
                };
              };
            };
            networking.firewall = {
              allowedTCPPorts = lib.mkOption {
                type = lib.types.listOf lib.types.int;
                default = [ ];
              };
              allowedUDPPorts = lib.mkOption {
                type = lib.types.listOf lib.types.int;
                default = [ ];
              };
            };
            assertions = lib.mkOption {
              type = lib.types.listOf lib.types.anything;
              default = [ ];
            };
            warnings = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
          };
          config.programs.nixarchy.enable = true;
        }
        settings
      ];
    }).config;
  sync =
    user: users:
    eval {
      programs.nixarchy.services.syncthing = {
        enable = true;
        inherit user;
      };
      users.users = users;
    };
  hasFailedAssertion =
    c: phrase: lib.any (a: !a.assertion && lib.hasInfix phrase a.message) c.assertions;
  syncCustom = sync "alice" {
    alice = {
      home = "/srv/alice";
      isNormalUser = true;
    };
  };
  syncNull = sync null { };
  syncMissing = sync "missing" { };
  syncEmpty = sync "empty" { empty = { }; };
  syncGenerated = eval (
    { config, ... }:
    {
      programs.nixarchy.services.syncthing = {
        enable = true;
        user = "syncthing";
      };
      # Nixpkgs defines this user's home from services.syncthing.dataDir.
      users.users.syncthing.home = config.services.syncthing.dataDir;
    }
  );
  urlHost = import ../modules/ollama-url-host.nix { inherit lib; };
  localAiSource = builtins.readFile ../modules/local-ai.nix;
  web =
    host:
    (eval {
      programs.nixarchy.services.open-webui.enable = true;
      services.ollama = {
        enable = true;
        inherit host;
      };
    }).services.open-webui.environment;
  flatpak =
    explicitOff:
    (eval (
      {
        programs.nixarchy.flatpaks.apps.geforce-now.enable = true;
      }
      // lib.optionalAttrs explicitOff { services.flatpak.enable = false; }
    )).services.flatpak.enable;
  cases = [
    {
      name = "Syncthing follows the selected user's home";
      ok =
        syncCustom.services.syncthing.dataDir == "/srv/alice"
        && syncCustom.services.syncthing.configDir == "/srv/alice/.config/syncthing";
    }
    {
      name = "Syncthing null user fails its existing assertion";
      ok = hasFailedAssertion syncNull "no user is set";
    }
    {
      name = "Syncthing undeclared user fails an assertion";
      ok = hasFailedAssertion syncMissing "must name a user with a home directory";
    }
    {
      name = "Syncthing var-empty home fails an assertion";
      ok = hasFailedAssertion syncEmpty "must name a user with a home directory";
    }
    {
      name = "Syncthing's generated system user fails without a home recursion";
      ok = hasFailedAssertion syncGenerated "must name a user with a home directory";
    }
    {
      name = "Local AI uses the shared IPv6 URL host";
      ok =
        urlHost "::1" == "[::1]"
        && urlHost "[::1]" == "[::1]"
        && urlHost "::" == "127.0.0.1"
        && lib.hasInfix "urlHost = import ./ollama-url-host.nix" localAiSource
        && lib.hasInfix "endpoint = \"http://\${urlHost}" localAiSource;
    }
    {
      name = "Open WebUI brackets bare IPv6";
      ok = (web "::1").OLLAMA_API_BASE_URL == "http://[::1]:11434";
    }
    {
      name = "Open WebUI retains bracketed IPv6";
      ok = (web "[::1]").OLLAMA_API_BASE_URL == "http://[::1]:11434";
    }
    {
      name = "Open WebUI uses loopback for wildcard IPv6";
      ok = (web "::").OLLAMA_API_BASE_URL == "http://127.0.0.1:11434";
    }
    {
      name = "Open WebUI retains IPv4 and hostname";
      ok =
        (web "127.0.0.1").OLLAMA_API_BASE_URL == "http://127.0.0.1:11434"
        && (web "models.local").OLLAMA_API_BASE_URL == "http://models.local:11434";
    }
    {
      name = "Open WebUI keeps telemetry disabled";
      ok = (web "::1").ANONYMIZED_TELEMETRY == "False";
    }
    {
      name = "Flatpak explicit disable wins";
      ok = flatpak true == false;
    }
    {
      name = "Flatpak selection enables by default";
      ok = flatpak false == true;
    }
  ];
in
pkgs.runCommand "robustness-modules" { } ''
  ${lib.concatMapStringsSep "\n" (c: ''
    if [ ${if c.ok then "1" else "0"} != 1 ]; then
      echo ${lib.escapeShellArg "FAIL: ${c.name}"} >&2
      exit 1
    fi
    echo ${lib.escapeShellArg c.name}
  '') cases}
  touch "$out"
''
