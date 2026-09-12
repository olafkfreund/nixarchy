# Open WebUI: a browser chat window over the models this machine already runs.
#
# Bundled rather than plain for one reason, and it is the reason somebody
# reports as a bug: Open WebUI's own default for OLLAMA_BASE_URL is
# localhost:11434, and nixarchy's Ollama is wherever services.ollama actually
# listens. Those agree until they do not -- a host that set its own port, or
# bound Ollama to a tailnet address -- and the symptom is a working UI with an
# empty model list and nothing on screen about why.
#
# The second reason is smaller and sharper: services.open-webui.environment
# carries upstream's telemetry-off defaults IN THE OPTION DEFAULT, and an
# option default is replaced rather than merged the moment anything defines
# the option. So a module that adds one variable there silently turns
# ANONYMIZED_TELEMETRY back on. They are restated below.
#
# Everything else stays upstream's. There is no nixarchy port, host, stateDir
# or openFirewall option here: those are one line each in services.open-webui,
# which is the vocabulary every wiki page and forum answer will use, and RFC 42
# is right that a copied option goes stale. See data/services.nix on the bar
# for "bundled".
{
  config,
  lib,
  ...
}:
let
  cfg = config.programs.nixarchy;
  svc = cfg.services.open-webui;

  ollama = config.services.ollama;

  # The address the UI dials, read off the server rather than off our own
  # options -- the same rule modules/local-ai.nix follows for the agents: a
  # host that already set services.ollama.port keeps it, and the client has to
  # follow the server to wherever it actually listens.
  #
  # A wildcard bind is not an address to connect TO. Ollama listening on
  # 0.0.0.0 or [::] is reachable at loopback, and a URL containing 0.0.0.0
  # fails in some HTTP clients and resolves to something unintended in others.
  ollamaHost =
    if
      builtins.elem ollama.host [
        "0.0.0.0"
        "[::]"
        "::"
      ]
    then
      "127.0.0.1"
    else
      ollama.host;
  ollamaUrl = "http://${ollamaHost}:${toString ollama.port}";
in
{
  options.programs.nixarchy.services.open-webui = {
    enable = lib.mkEnableOption ''
      Open WebUI, a browser chat interface pointed at this machine's Ollama.

      Off by default like everything else here. Enabling it starts a service on
      port 8080 whose first visitor creates the administrator account, so it
      stays on loopback until you say otherwise -- `services.open-webui.host`
      and `.openFirewall` are upstream's and this module does not touch them.

      Useful beside `programs.nixarchy.localAi`, which is what puts a model on
      the machine in the first place. It works without it, pointed at an Ollama
      you run yourself; it does not work with no Ollama at all, and says so at
      evaluation rather than showing you an empty model list
    '';
  };

  config = lib.mkIf (cfg.enable && svc.enable) {
    services.open-webui = {
      # Scalar, so mkDefault -- see the header of modules/services.
      enable = lib.mkDefault true;

      # An attrset, so plain assignment: mkDefault on a merging type is
      # dropped before the merge, and a user adding one variable of their own
      # would take the base URL with it.
      #
      # The three telemetry keys are upstream's option DEFAULT, restated
      # because defining this option replaces that default outright. Dropping
      # them here would be nixarchy turning analytics on for somebody.
      environment = {
        OLLAMA_API_BASE_URL = ollamaUrl;
        SCARF_NO_ANALYTICS = "True";
        DO_NOT_TRACK = "True";
        ANONYMIZED_TELEMETRY = "False";
      };
    };

    assertions = [
      {
        assertion = ollama.enable;
        message = ''
          programs.nixarchy.services.open-webui is on and this machine runs no
          Ollama, so the UI would start with nothing to talk to.

          Either let nixarchy run one, which also picks the build from the GPU
          this configuration declares:

            programs.nixarchy.localAi.enable = true;

          or enable services.ollama yourself. To point the UI at a model server
          on another machine instead, set the base URL by hand and this module
          is not what you want:

            services.open-webui.environment.OLLAMA_API_BASE_URL = "http://host:11434";
        '';
      }
    ];

    warnings = lib.optional config.services.open-webui.openFirewall ''
      programs.nixarchy.services.open-webui: the firewall is open on port
      ${toString config.services.open-webui.port}, so anyone who can reach this
      machine can reach the UI. Open WebUI has accounts, and the FIRST visitor
      to an empty instance becomes the administrator -- so open this only after
      you have logged in once, or leave it closed and reach it over Tailscale.
    '';
  };
}
