{
  lib,
  rustPlatform,
  installShellFiles,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "ttfx";
  version = "0.3.2";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "ttfx";
    tag = "v${finalAttrs.version}";
    hash = "sha256-bwFjC6ZkZibkgXjoYVH2VuqqeXklGR9kmRl2fTitWBU=";
  };

  cargoHash = "sha256-DNrg12MNqBcQi6yvoJObM1gtE90iGBCxeQ3RwueYCE4=";

  nativeBuildInputs = [ installShellFiles ];

  # `--print-completion <SHELL>`, not a `completions` subcommand -- and bash and
  # zsh only, which is what clap_complete is wired for here. Generated from the
  # binary rather than written out, so they cannot drift from its arguments.
  postInstall = ''
    installShellCompletion --cmd ttfx \
      --bash <($out/bin/ttfx --print-completion bash) \
      --zsh  <($out/bin/ttfx --print-completion zsh)
  '';

  meta = {
    description = "Terminal text effects as a single static binary, a Rust port of terminaltexteffects";
    homepage = "https://github.com/omacom/ttfx";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "ttfx";
  };
})
