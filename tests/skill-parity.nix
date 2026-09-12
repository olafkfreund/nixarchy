{ inputs, pkgs }:
# Upstream's own SKILL.md, section by section, against what this port decided.
#
# pkgs/omarchy/default.nix replaces upstream's skill wholesale -- correctly, and
# docs/manual/ai.md says why. data/skill-parity.nix is the record of what that
# replacement decided, and this holds it to the claim in both directions:
#
#   an upstream section with no row       unclassified
#   a row upstream no longer has          stale
#   a `preserved` heading missing here    the claim is false
#   an anchor that greps nothing here     the claim is unproven
#   a section whose upstream text moved   re-audit, then re-pin
#
# The upstream side is inputs.omarchy -- the same source pkgs/omarchy vendors,
# so the comparison is against exactly what was replaced -- and our side is the
# skill source tree rather than the built package, which keeps this an
# evaluation plus a grep rather than a package build.
#
# Why: #643, and the wider argument in #640.
pkgs.runCommand "nixarchy-skill-parity"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    upstream = inputs.omarchy;
    skill = ../pkgs/omarchy/skills/nixarchy;
    manifest = ../data/skill-parity.nix;
    script = ../.github/scripts/check-skill-parity.py;
  }
  ''
    python3 $script \
      --upstream "$upstream" \
      --skill "$skill" \
      --manifest "$manifest"
    touch $out
  ''
