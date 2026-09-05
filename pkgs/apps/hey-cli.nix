{
  lib,
  stdenvNoCC,
  fetchurl,
  writeShellApplication,
  curl,
  jq,
  gnused,
  nix,
  coreutils,
  gnugrep,
}:
let
  version = "1.4.1";

  # Straight from the release's own checksums.txt, which upstream signs with a
  # keyless Sigstore bundle -- not from a local download. Same reasoning as
  # pkgs/apps/once.nix: these should be the artefacts basecamp published, not
  # whatever a machine here happened to fetch.
  hashes = {
    "x86_64-linux" = "18c4a5eb86dc98a7416fd6c452537a0968df7080cda6c20bd9192f06d95e58b1";
    "aarch64-linux" = "2a7e3124e8b09313f013dee9f72bef7d302cff27e5e2d7f36571c30b5289ab58";
  };
  arches = {
    "x86_64-linux" = "amd64";
    "aarch64-linux" = "arm64";
  };

  sources = lib.mapAttrs (
    system: sha256:
    fetchurl {
      url = "https://github.com/basecamp/hey-cli/releases/download/v${version}/hey_${version}_linux_${arches.${system}}.tar.gz";
      inherit sha256;
    }
  ) hashes;
in
stdenvNoCC.mkDerivation {
  pname = "hey-cli";
  inherit version;

  src =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "hey-cli: no binary published for ${stdenvNoCC.hostPlatform.system}");

  # The tarball is just the binary and its docs, with no directory above them.
  sourceRoot = ".";
  strictDeps = true;

  # No autoPatchelfHook, unlike once: upstream ships a statically linked Go
  # binary, so there is no interpreter to rewrite and nothing to link against.
  # Verified rather than assumed --
  #   hey: ELF 64-bit LSB executable, x86-64, statically linked, Go, stripped
  # and the unpatched binary runs on NixOS. Adding the hook anyway would be
  # harmless but would say something untrue about why this works.
  installPhase = ''
    runHook preInstall
    install -Dm755 hey $out/bin/hey
    runHook postInstall
  '';

  # Same shape as once's, and here for the same reason: the updater has to move
  # both architectures together or it produces a tree that builds on x86 and
  # not on ARM. CI proves every rewrite with a build before it can be committed
  # (.github/workflows/update.yml), and those PRs are merged by a human because
  # a build is not proof the CLI still talks to HEY.
  passthru.updateScript = writeShellApplication {
    name = "update-hey-cli";
    runtimeInputs = [
      curl
      jq
      gnused
      nix
      coreutils
      gnugrep
    ];
    text = ''
      file="''${1:-pkgs/apps/hey-cli.nix}"
      [ -f "$file" ] || { echo "no $file (run from the repo root)" >&2; exit 1; }

      current=$(sed -n 's/.*version = "\([^"]*\)".*/\1/p' "$file" | head -1)
      latest=$(curl -fsSL https://api.github.com/repos/basecamp/hey-cli/releases/latest \
        | jq -r '.tag_name' | sed 's/^v//')

      if [ -z "$latest" ] || [ "$latest" = "null" ]; then
        echo "hey-cli: could not read a release tag from GitHub" >&2
        exit 1
      fi
      if [ "$current" = "$latest" ]; then
        echo "hey-cli: already at $latest"
        exit 0
      fi
      echo "hey-cli: $current -> $latest"

      # Upstream publishes a checksums.txt per release, so take the hashes from
      # it rather than re-downloading two 37 MB tarballs to compute what they
      # already state.
      sums=$(curl -fsSL "https://github.com/basecamp/hey-cli/releases/download/v$latest/checksums.txt")

      for pair in "x86_64-linux:amd64" "aarch64-linux:arm64"; do
        key=''${pair%%:*}
        arch=''${pair##*:}
        # Anchored to end of line: since 1.4.1 the release also publishes a
        # .sbom.json beside each tarball, and an unanchored match returned
        # both hashes -- two lines in $hex, which then broke the sed below
        # with "unterminated `s' command".
        hex=$(echo "$sums" | grep "hey_''${latest}_linux_''${arch}.tar.gz\$" | cut -d' ' -f1 || true)
        if [ -z "$hex" ]; then
          echo "hey-cli: checksums.txt names no hey_''${latest}_linux_''${arch}.tar.gz" >&2
          exit 1
        fi
        before=$(grep -c "$hex" "$file" || true)
        sed -i -E "s|(\"$key\"[[:space:]]*=[[:space:]]*)\"[0-9a-f]{64}\"|\1\"$hex\"|" "$file"
        after=$(grep -c "$hex" "$file" || true)
        if [ "$before" = "$after" ]; then
          # A bumped version beside a stale hash builds nowhere and reports
          # success here, so refuse rather than hand that to a reviewer.
          echo "hey-cli: could not rewrite the hash for '$key' in $file" >&2
          exit 1
        fi
      done

      sed -i -E "0,/version = \"[^\"]*\"/s//version = \"$latest\"/" "$file"
      echo "hey-cli: rewrote $file to $latest"
    '';
  };

  meta = {
    description = "CLI and TUI for HEY email, and the interface HEY Agents drives";
    homepage = "https://www.hey.com/agents/";
    downloadPage = "https://github.com/basecamp/hey-cli/releases";
    license = lib.licenses.mit;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];

    # nixpkgs already has a `hey` and it is an unrelated HTTP load generator,
    # so the attribute is hey-cli while the binary keeps upstream's name. The
    # Install menu and nixarchy-doctor both key on mainProgram to decide
    # whether an app is already present, and would look for `hey-cli` without
    # this -- which is the vscode/code trap the doctor exists to avoid.
    mainProgram = "hey";
  };
}
