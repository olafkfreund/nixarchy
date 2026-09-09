{ inputs, pkgs }:
# Every command this port does not ship verbatim, classified and checked.
#
# data/bin-ledger.nix claims which of Omarchy's commands differ here and why.
# This holds it to that claim, in BOTH directions:
#
#   a file that differs with no row     unclassified
#   a row whose derived class moved     stale
#   a row for a bin that went vendor    a rubber stamp, deleted
#
# The classification is DERIVED -- `cmp` of shipped against upstream ignoring
# line 1, because patchShebangs rewrites the shebang and nothing else -- and
# then compared with what the row says. So the ledger cannot be satisfied by
# editing the ledger, which is the whole point: a hand list that only agrees
# with itself proves nothing. Same argument omarchy-patched-files.sh makes
# about file names, applied to classification.
#
# It also subsumes build.yml's pacman allowlist. Those 24 entries were already
# ledger rows in everything but name -- per-command, with a reason, failing in
# both directions -- so they are rows now, and the inline list is deleted
# rather than left to drift beside this one.
#
# The upstream tree is inputs.omarchy, the same source pkgs/omarchy builds
# from, so the comparison is against exactly what was vendored rather than
# against a re-fetch that could differ.
pkgs.runCommand "nixarchy-bin-ledger"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    upstream = inputs.omarchy;
    shipped = pkgs.nixarchy-omarchy or pkgs.omarchy;
    ledger = ../data/bin-ledger.nix;
    nixbin = ../pkgs/omarchy/nix-bin;
    script = ../.github/scripts/check-bin-ledger.py;
  }
  ''
    python3 $script \
      --upstream "$upstream" \
      --shipped "$shipped/share/omarchy" \
      --nix-bin "$nixbin" \
      --ledger "$ledger"
    touch $out
  ''
