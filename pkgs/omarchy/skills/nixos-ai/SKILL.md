---
name: nixos-ai
description: >
  REQUIRED for running local AI models on this NixOS machine — Ollama, Open WebUI,
  llama.cpp, ComfyUI, Stable Diffusion, Whisper, and connecting local models to
  coding agents. Use when asked to install Ollama, run an LLM locally, pull or
  declare a model, get a model onto the GPU, expose a model to another machine,
  fix slow or CPU-only inference, or point Claude Code / opencode / Continue at a
  local endpoint. Triggers: ollama, llama.cpp, open-webui, local LLM, local AI,
  llama3, qwen, deepseek, mistral, gguf, model, inference, embeddings,
  OLLAMA_HOST, "runs on CPU", "model too slow", stable diffusion, comfyui, whisper.
  For the GPU driver and CUDA/ROCm stack underneath, use the `nixos-gpu` skill.
---

# NixOS Local AI Skill

Local inference on NixOS is one option away from working — and then one *very*
specific option away from actually using the GPU.

**Prerequisite: the GPU stack must already work.** `nvidia-smi` or `rocminfo` has
to return your card before any of this is worth attempting. If it does not, that
is the `nixos-gpu` skill, and it comes first. Ollama will happily fall back to
the CPU and give you no error at all — just 20x less speed.

## Ollama

```nix
{ pkgs, ... }:
{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;      # or ollama-rocm, ollama-vulkan, ollama-cpu
    loadModels = [ "llama3.2" "qwen2.5-coder:7b" "nomic-embed-text" ];
  };
}
```

That is the whole thing: `nixos-rebuild switch`, then `ollama run llama3.2`.

### Picking the package — the part everyone gets wrong

**There is no `services.ollama.acceleration` option.** It existed, it is gone, and
every LLM trained before its removal will suggest it. The eval fails with "option
does not exist". Acceleration is chosen by picking the package:

| Hardware | `package =` |
|---|---|
| NVIDIA | `pkgs.ollama-cuda` |
| AMD | `pkgs.ollama-rocm` |
| Anything else with a working Vulkan driver | `pkgs.ollama-vulkan` |
| No GPU / force CPU | `pkgs.ollama-cpu` |

Leaving `package` unset gives you plain `pkgs.ollama`, which follows
`nixpkgs.config.cudaSupport`/`rocmSupport` and otherwise means **CPU**. Setting
the explicit variant is better than turning on a global flag: you get the GPU
build without rebuilding half of nixpkgs.

### Models, declaratively

`loadModels` pulls the listed models once `ollama.service` is up, via a generated
`ollama-model-loader.service`. Models are a large download, not a Nix build — the
first activation after adding one takes as long as the network does, and the
rebuild itself does not block on it.

```nix
services.ollama = {
  loadModels = [ "qwen2.5-coder:7b" ];
  syncModels = true;      # also DELETES any model not listed here
};
```

`syncModels = true` makes the declaration authoritative — which is the Nix
spirit, and will silently remove a model someone pulled by hand. Say that out
loud before enabling it.

Models default to `/var/lib/private/ollama/models` (the service runs under
`DynamicUser` unless you set `user`). A model directory is tens of gigabytes;
point it at the roomy disk if `/var` is small:

```nix
services.ollama.modelsDir = "/data/ollama-models";
```

**It is `modelsDir`, not `models`.** The option was renamed; the old name still
evaluates but emits a deprecation warning, and most published examples — and
most model training data — still say `models`.

Browse names at <https://ollama.com/library>. Rough VRAM rule: a Q4-quantised
model needs about `params × 0.6` GB — a 7B fits in 6 GB, a 14B in ~10 GB, a 32B
wants 24 GB. Exceed VRAM and it spills to system RAM and crawls; that is the
usual cause of "it worked yesterday and now it's slow" after switching models.

### AMD cards ROCm doesn't officially support

Same override as in `nixos-gpu`, but scoped to the service:

```nix
services.ollama.rocmOverrideGfx = "10.3.0";     # sets HSA_OVERRIDE_GFX_VERSION
```

### Reaching it from other machines

Ollama listens on `127.0.0.1:11434` by default, which is the right default.

```nix
services.ollama = {
  host = "0.0.0.0";
  openFirewall = true;      # opens services.ollama.port on the LAN
};
```

**Ollama has no authentication.** Anything that can reach the port can use the
GPU and read every model. Only do this on a network you trust, or better, put it
on Tailscale and bind to the tailnet address instead of `0.0.0.0`.

### Tuning

```nix
services.ollama.environmentVariables = {
  OLLAMA_KEEP_ALIVE = "30m";      # keep the model in VRAM between requests
  OLLAMA_NUM_PARALLEL = "2";      # concurrent requests per model
  OLLAMA_CONTEXT_LENGTH = "8192"; # default context; more = more VRAM
};
```

These reach the *service* only, not an `ollama run` you type yourself — which is
what you want, since `ollama run` is a client of that server.

## Open WebUI

A ChatGPT-like browser front end for the local models:

```nix
services.open-webui = {
  enable = true;
  port = 8080;
  environment = {
    OLLAMA_API_BASE_URL = "http://127.0.0.1:11434";
    WEBUI_AUTH = "False";              # single-user machine; drop for multi-user
    ANONYMIZED_TELEMETRY = "False";
    DO_NOT_TRACK = "True";
  };
};
```

Then <http://localhost:8080>. Leave `openFirewall` off unless the machine is
meant to serve other people, and if it is, set up auth rather than exposing an
unauthenticated UI onto the LAN.

## llama.cpp and other runtimes

For GGUF files you manage yourself, or when you need a knob Ollama does not
expose:

```nix
environment.systemPackages = [
  (pkgs.llama-cpp.override { cudaSupport = true; })    # or rocmSupport
];
```

Other things people ask for, and their attribute names:

| Want | Package / option |
|---|---|
| Image generation | `pkgs.comfyui` (`nixpkgs.config.cudaSupport` for GPU), or a container |
| Speech to text | `pkgs.whisper-cpp`, `pkgs.whisper-ctranslate2` |
| Text to speech | `pkgs.piper-tts` |
| Python ML env | a devShell with `python3.withPackages (ps: [ ps.torch ps.transformers ])` |
| Vector DB | `services.qdrant.enable`, or Postgres with `pgvector` |

**Do not `pip install` into the system.** Python on NixOS wants either a
`devShell`, a `python3.withPackages` environment, or `uv`/`venv` inside a project
directory. A `pip install --user` that links against system libraries will break
at the next rebuild, and the failure will look like a driver problem.

## Wiring agents to the local model

Once Ollama is up, an OpenAI-compatible endpoint exists at
`http://localhost:11434/v1`. Most agent tooling accepts that:

```bash
export OLLAMA_HOST=127.0.0.1:11434                  # for the ollama CLI itself
export OPENAI_BASE_URL=http://localhost:11434/v1    # many OpenAI-compatible clients
export OPENAI_API_KEY=ollama                        # ignored, but often required to be set
```

For a coding agent, `qwen2.5-coder` and `deepseek-coder-v2` are the usual local
choices. Be honest with the user about the gap: a 7B local model is a real
downgrade from a frontier model for agentic work, and is best used for
completion, quick edits, and offline work rather than long autonomous tasks.

## Troubleshooting

```bash
systemctl status ollama
journalctl -u ollama -b --no-pager | tail -50
curl -s localhost:11434/api/tags | jq '.models[].name'    # what is actually installed
ollama ps                                                  # loaded now, and on GPU or CPU
```

`ollama ps` is the one that answers the important question — its `PROCESSOR`
column says `100% GPU`, `100% CPU`, or a split. Anything but full GPU is the
problem.

| Symptom | Cause |
|---|---|
| `error: option 'services.ollama.acceleration' does not exist` | Removed. Set `package = pkgs.ollama-cuda` etc. |
| Works, but slow; `ollama ps` says CPU | Default `pkgs.ollama` = CPU build. Set the variant |
| Partial GPU split in `ollama ps` | Model bigger than VRAM. Smaller model or lower quant |
| `no GPU detected` in the journal, NVIDIA | Driver layer. Check `nvidia-smi` first — `nixos-gpu` skill |
| AMD: `invalid ISA` in the journal | Set `services.ollama.rocmOverrideGfx` |
| Model download fails on rebuild | Network, or a wrong model name. `ollama pull` it by hand to see the real error |
| Out of disk after adding models | Move `services.ollama.modelsDir` to a bigger disk |
| Open WebUI shows no models | `OLLAMA_API_BASE_URL` wrong, or ollama not running |

## Rules

- **Check the GPU stack before touching Ollama.** Most "Ollama is slow" reports
  are a driver or package-variant problem one layer down.
- **Always set `services.ollama.package` explicitly.** The default is CPU, and
  the failure is silent.
- **Never suggest `services.ollama.acceleration`.** It does not exist any more,
  and neither does `services.ollama.models` (it is `modelsDir`). When unsure of
  an option name, read the module rather than recalling it — see the
  `nixos-services` skill for how.
- **Warn before `syncModels = true`** — it deletes models not in the list.
- **Warn before `host = "0.0.0.0"`** — there is no authentication on that port.
- Model weights are not managed by Nix. They are large, mutable, and downloaded
  at runtime; `nixos-rebuild --rollback` does not roll them back.
