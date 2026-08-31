{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  docker,
  makeWrapper,
  writeShellApplication,
  curl,
  jq,
  gnused,
  nix,
  coreutils,
  gnugrep,
}:
let
  version = "0.3.2";
  # Hashes come from omarchy-pkgs' own PKGBUILD rather than from a local
  # download, so they are the same artefacts Omarchy ships on Arch.
  # Keyed by system so the updater can rewrite each hash by name; see
  # pkgs/apps/update-script.nix.
  hashes = {
    "x86_64-linux" = "e1da40a0952879580e43623d6fd6002a391ee469b642c98ecddbe00374facbb6";
    "aarch64-linux" = "9bd644e1557521b0b8cab93ba3841747cbee0390aa3aa020bd91bfa66ac51dec";
  };
  urls = {
    "x86_64-linux" = "https://github.com/basecamp/once/releases/download/v${version}/once-linux-amd64";
    "aarch64-linux" = "https://github.com/basecamp/once/releases/download/v${version}/once-linux-arm64";
  };
  sources = lib.mapAttrs (
    system: sha256:
    fetchurl {
      url = urls.${system};
      inherit sha256;
    }
  ) hashes;
in
stdenvNoCC.mkDerivation {
  pname = "once";
  inherit version;

  src =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "once: no binary published for ${stdenvNoCC.hostPlatform.system}");

  dontUnpack = true;
  strictDeps = true;

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/once
    runHook postInstall
  '';

  # once drives docker for everything it does; without it on PATH the first
  # thing a user sees is a command-not-found from inside a TUI.
  postFixup = ''
    wrapProgram $out/bin/once --prefix PATH : ${lib.makeBinPath [ docker ]}
  '';

  # passthru.updateScript is where nixpkgs looks for this, so `nix-update` and
  # nixpkgs' own update.nix find it without any wiring of ours.
  #
  # Not nix-update itself: it rewrites one hash, and this pins one binary per
  # architecture from a single release, so a bump has to move both together or
  # produce a tree that builds on x86 and not on ARM. Written out rather than
  # generated because `once` is the only package here still pinned by hand --
  # everything else is in nixpkgs or comes from a flake, and both update when
  # a user runs `nix flake update`.
  #
  # Every rewrite is proved by a build before it can be committed; see
  # .github/workflows/update.yml. A build is not proof the app still *works*,
  # which is why those PRs are for a human to merge rather than automerged.
  passthru.updateScript = writeShellApplication {
    name = "update-once";
    runtimeInputs = [
      curl
      jq
      gnused
      nix
      coreutils
      gnugrep
    ];
    text = ''
      file="''${1:-pkgs/apps/once.nix}"
      [ -f "$file" ] || { echo "no $file (run from the repo root)" >&2; exit 1; }

      current=$(sed -n 's/.*version = "\([^"]*\)".*/\1/p' "$file" | head -1)
      latest=$(curl -fsSL https://api.github.com/repos/basecamp/once/releases/latest \
        | jq -r '.tag_name' | sed 's/^v//')

      if [ -z "$latest" ] || [ "$latest" = "null" ]; then
        echo "once: could not read a release tag from GitHub" >&2
        exit 1
      fi
      if [ "$current" = "$latest" ]; then
        echo "once: already at $latest"
        exit 0
      fi
      echo "once: $current -> $latest"

      for pair in "x86_64-linux:amd64" "aarch64-linux:arm64"; do
        key=''${pair%%:*}
        arch=''${pair##*:}
        url="https://github.com/basecamp/once/releases/download/v$latest/once-linux-$arch"
        echo "  prefetching $key"
        # --type sha256 keeps the plain hex the derivation already uses, so the
        # diff is one hash per line rather than a format change.
        hash=$(nix-prefetch-url --type sha256 "$url" 2>/dev/null | tail -1)
        if [ -z "$hash" ]; then
          echo "once: could not fetch $url" >&2
          exit 1
        fi
        hex=$(nix hash to-base16 --type sha256 "$hash" 2>/dev/null || echo "$hash")
        before=$(grep -c "$hex" "$file" || true)
        sed -i -E "s|(\"$key\"[[:space:]]*=[[:space:]]*)\"[0-9a-f]{64}\"|\1\"$hex\"|" "$file"
        after=$(grep -c "$hex" "$file" || true)
        if [ "$before" = "$after" ]; then
          # Bumping the version while leaving a stale hash produces a file that
          # reports success and then fails to build, so refuse rather than hand
          # that to a reviewer.
          echo "once: could not rewrite the hash for '$key' in $file" >&2
          exit 1
        fi
      done

      sed -i -E "0,/version = \"[^\"]*\"/s//version = \"$latest\"/" "$file"
      echo "once: rewrote $file to $latest"
    '';
  };

  meta = {
    description = "CLI and TUI for installing and managing self-hosted web applications";
    homepage = "https://github.com/basecamp/once";
    license = lib.licenses.mit;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "once";
  };
}
