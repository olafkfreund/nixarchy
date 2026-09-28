{
  lib,
  rustPlatform,
  installShellFiles,
  fetchFromGitHub,
  nix-update,
  writeShellApplication,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "ttfx";
  version = "0.5.0";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "ttfx";
    tag = "v${finalAttrs.version}";
    hash = "sha256-ZeWRyo9zturjRcH23SDgFOKoPOSY6nGMFzGeJAoDapk=";
  };

  cargoHash = "sha256-ntoj5bmAa9U2+3K1UX6HL0t6MjfCYQNe5LuiuNJ/CnY=";

  nativeBuildInputs = [ installShellFiles ];

  # `--print-completion <SHELL>`, not a `completions` subcommand -- and bash and
  # zsh only, which is what clap_complete is wired for here. Generated from the
  # binary rather than written out, so they cannot drift from its arguments.
  postInstall = ''
    installShellCompletion --cmd ttfx \
      --bash <($out/bin/ttfx --print-completion bash) \
      --zsh  <($out/bin/ttfx --print-completion zsh)
  '';

  # Same shape as omawrite's, and the reasoning lives there. The one thing
  # this package adds is cargoHash, and it is the reason nix-update earns its
  # keep here: it recomputes the vendored-dependency hash too, which a
  # hand-rolled sed script has no honest way to know. Proven by winding
  # version back to 0.3.1 and watching it restore 0.3.2's exact hash AND
  # cargoHash.
  passthru.updateScript = writeShellApplication {
    name = "update-ttfx";
    runtimeInputs = [ nix-update ];
    text = ''
      [ -f flake.nix ] || { echo "ttfx: run from the repo root" >&2; exit 1; }
      nix-update --flake ttfx
    '';
  };

  meta = {
    description = "Terminal text effects as a single static binary, a Rust port of terminaltexteffects";
    homepage = "https://github.com/omacom/ttfx";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "ttfx";
  };
})
