{
  inputs,
  pkgs,
  installScript,
}:
let
  fixture = pkgs.runCommand "reinstall-image-fixture" { } ''
    mkdir -p $out/hosts/alpha
    printf 'fixture\n' > $out/hosts/alpha/default.nix
    printf '{ }\n' > $out/flake.nix
    printf '*.pem\n' > $out/.gitignore
    printf 'tracked despite the ignore rule\n' > $out/hosts/alpha/cert.pem
  '';
  flake = {
    outPath = fixture;
    nixosConfigurations.alpha = { };
  };
  image = inputs.self.lib.mkUserIso {
    inherit flake;
    host = "alpha";
  };
  wrong =
    builtins.tryEval
      (inputs.self.lib.mkUserIso {
        inherit flake;
        host = "wrong";
      }).installerLauncher;
in
pkgs.runCommand "nixarchy-reinstall-image"
  {
    nativeBuildInputs = [ pkgs.git ];
    launcher = image.installerLauncher;
    publishedLauncher = inputs.self.nixosConfigurations.iso-net.config.system.build.installerLauncher;
    wrongRejected = !wrong.success;
  }
  ''
    [ "$wrongRejected" = 1 ] || { echo "mkUserIso accepted a host absent from the flake" >&2; exit 1; }
    repo=$(grep -oE 'file:///nix/store/[^ ]+' "$launcher" | head -1 || true)
    [ -n "$repo" ] || { echo "personal launcher names no store repository" >&2; exit 1; }
    repoPath=''${repo#file://}
    HOME=$PWD
    git config --global --add safe.directory "$repoPath"
    [ "$(git --git-dir="$repoPath" rev-list --count HEAD)" = 1 ] || { echo "image repository has more than one commit" >&2; exit 1; }
    [ -z "$(git --git-dir="$repoPath" remote)" ] || { echo "image repository has a remote" >&2; exit 1; }
    git --git-dir="$repoPath" cat-file -e HEAD:hosts/alpha/cert.pem 2>/dev/null || { echo "image repository dropped a tracked file its .gitignore matches" >&2; exit 1; }

    cat() { if [ "$1" = /proc/cmdline ]; then printf '%s\n' "$CMDLINE"; else command cat "$@"; fi; }
    exec() { shift; : > got; [ "$#" -eq 0 ] || printf '%s\n' "$@" > got; }
    run_launcher() { (CMDLINE=$1; . "$2"); }
    run_launcher "" "$launcher"
    printf '%s\n' --from "$repo" --host alpha > want
    cmp want got || { echo "personal launcher did not pass its pair" >&2; exit 1; }
    run_launcher 'nixarchy.from=https://example/repo nixarchy.host=other' "$launcher"
    printf '%s\n' --from https://example/repo --host other > want
    cmp want got || { echo "kernel pair did not win" >&2; exit 1; }
    run_launcher 'nixarchy.host=other' "$launcher"
    printf '%s\n' --host other > want
    cmp want got || { echo "partial kernel pair was combined with image pair" >&2; exit 1; }
    sed -n '/^main()/,/^}/p' ${installScript} > main.sh
    if ( from_repo= from_host=; . ./main.sh; main --host other ) > refusal 2>&1; then
      echo "main accepted --host without --from" >&2; exit 1
    fi
    grep -Fq -- '--host only means something with --from' refusal || exit 1
    run_launcher 'nixarchy.from=https://example/repo' "$launcher"
    printf '%s\n' --from https://example/repo > want
    cmp want got || { echo "partial kernel pair was combined with image pair" >&2; exit 1; }
    if ( from_repo= from_host=; . ./main.sh; main --from https://example/repo ) > refusal 2>&1; then
      echo "main accepted --from without --host" >&2; exit 1
    fi
    grep -Fq -- '--from needs --host' refusal || exit 1
    run_launcher "" "$publishedLauncher"
    [ ! -s got ] || { echo "published launcher added a personal host" >&2; exit 1; }

    sed -n '/^clone_repo()/,/^}/p' ${installScript} > clone.sh
    sed -n '/^finish_clone()/,/^}/p' ${installScript} >> clone.sh
    . ./clone.sh
    from_repo=$repo from_host=alpha
    clone_repo > clone.out
    [ "$from_host_exists" = true ] && [ -f "$work/hosts/alpha/default.nix" ] || {
      echo "carried repository did not describe alpha" >&2; exit 1;
    }
    [ -z "$(git -C "$work" remote)" ] || { echo "store remote survived clone_repo" >&2; exit 1; }
    from_host=beta
    clone_repo > clone-beta.out
    [ "$from_host_exists" = false ] || { echo "absent host looked existing" >&2; exit 1; }
    mkdir -p template/host
    printf 'new host\n' > template/host/default.nix
    TEMPLATE=$PWD/template
    substitute_host_files() { :; }
    finish_clone >> clone-beta.out
    grep -Fq 'has no beta; adding it' clone-beta.out || { echo "absent host did not enter adding branch" >&2; exit 1; }
    touch "$out"
  ''
