{
  lib,
  buildGo127Module,
  fetchFromGitHub,
  nix-update,
  writeShellApplication,
}:
buildGo127Module (finalAttrs: {
  pname = "omarchy-speedtest";
  version = "0.2.1";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "omarchy-speedtest";
    tag = "v${finalAttrs.version}";
    hash = "sha256-q3KJ+FS2xuTNzgRal3rfhXot0aFUkD01+PZtq0sq+YQ=";
  };

  vendorHash = null;

  # Upstream's suite times real TCP windows over localhost, and on a loaded CI
  # runner a window's byte count drifts by about 1% (#1485). The session probe
  # covers what this package must do here: be the client the script execs.
  doCheck = false;

  passthru.updateScript = writeShellApplication {
    name = "update-omarchy-speedtest";
    runtimeInputs = [ nix-update ];
    text = ''
      [ -f flake.nix ] || { echo "omarchy-speedtest: run from the repo root" >&2; exit 1; }
      nix-update --flake omarchy-speedtest
    '';
  };

  meta = {
    description = "Omarchy's network speed test client for speed.omarchy.org";
    homepage = "https://github.com/omacom/omarchy-speedtest";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "omarchy-speedtest";
  };
})
