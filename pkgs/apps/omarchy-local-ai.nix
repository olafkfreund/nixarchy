{
  lib,
  stdenv,
  fetchFromGitHub,
  python3,
  iproute2,
  nix-update,
  writeShellApplication,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "omarchy-local-ai";
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "omarchy-local-ai";
    tag = "v${finalAttrs.version}";
    hash = "sha256-VZLEo0rTepPdZCJfZk+bHATpWTs5SyvSFvVK4RS9wQY=";
  };

  nativeBuildInputs = [ python3 ];

  # Before the tests too: engine-test.sh runs the source tree's entry script
  # through a symlink, and #!/usr/bin/python3 does not exist in the sandbox.
  postPatch = ''
    patchShebangs omarchy-local-ai tests
  '';

  # The entry script finds agent_local.py and the catalog through
  # realpath(__file__), so the whole tree lives in share/ and bin/ only links.
  # No PATH wrapping: podman and systemctl must be the system's own.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/omarchy-local-ai $out/bin
    cp -r . $out/share/omarchy-local-ai
    rm -rf $out/share/omarchy-local-ai/{bench,tools,tests}
    ln -s $out/share/omarchy-local-ai/omarchy-local-ai $out/bin/omarchy-local-ai
    install -Dm644 LICENSE $out/share/licenses/omarchy-local-ai/LICENSE

    runHook postInstall
  '';

  doInstallCheck = true;
  # 0.6.0's pair tests read the fabric interface with ip; at runtime the system's own is used.
  nativeInstallCheckInputs = [ iproute2 ];
  # The Quadlet-generator part of engine-test.sh skips itself where podman's
  # generator is absent, as in the sandbox. tests/ and tools/bench are needed
  # by the test, so it runs against the source tree; validate runs on the install.
  installCheckPhase = ''
    runHook preInstallCheck

    bash tests/engine-test.sh
    export HOME=$(mktemp -d) PYTHONDONTWRITEBYTECODE=1
    $out/bin/omarchy-local-ai validate $out/share/omarchy-local-ai

    runHook postInstallCheck
  '';

  # Same shape as hype's.
  passthru.updateScript = writeShellApplication {
    name = "update-omarchy-local-ai";
    runtimeInputs = [ nix-update ];
    text = ''
      [ -f flake.nix ] || { echo "omarchy-local-ai: run from the repo root" >&2; exit 1; }
      nix-update --flake omarchy-local-ai
    '';
  };

  meta = {
    description = "Omarchy's local model runner: rootless Podman engine and recipe catalog";
    homepage = "https://github.com/omacom/omarchy-local-ai";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "omarchy-local-ai";
  };
})
