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
