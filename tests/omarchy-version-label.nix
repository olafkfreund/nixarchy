# #1371: the label a dev Omarchy commit gets, and that stable/edge keep theirs.
{
  pkgs,
  omarchy,
  omarchyVersion,
  lock,
}:
let
  label = import ../pkgs/omarchy/version-label.nix;
  inherit (pkgs.lib) assertMsg;
  pin = "a111111111111111111111111111111111111111";
  other = {
    rev = "b222222222222222222222222222222222222222";
    lastModifiedDate = "20261019180000";
    shortRev = "2d3aa60";
  };
in
assert assertMsg (
  label {
    version = "4.0.5";
    pinnedRev = pin;
    input = {
      rev = pin;
    };
  } == "4.0.5"
) "version-label: the pinned rev must keep the literal version";
assert assertMsg (
  label {
    version = "4.0.5";
    pinnedRev = pin;
    input = other;
  } == "dev-20261019-2d3aa60"
) "version-label: another rev must read dev-<date>-<shortRev>";
assert assertMsg (
  label {
    version = "4.0.5";
    pinnedRev = pin;
    input = { };
  } == "dev-unknown-unknown"
) "version-label: an input with no rev or date must read dev-unknown-unknown";
assert assertMsg (
  label {
    version = "4.0.5";
    pinnedRev = null;
    input = { };
  } != "4.0.5"
) "version-label: a null pin must not match a rev-less input";
assert assertMsg (
  omarchy.version == omarchyVersion
) "version-label: the flake's own omarchy.version must equal omarchyVersion (wiring)";
# #1407: omarchyVersion must name what flake.lock pins: the tag on stable, the
# locked rev on edge. Dev pins evaluate in the user's flake and never reach here.
assert
  let
    pin = lock.nodes.omarchy;
    want =
      if pin.original ? ref then
        "v${omarchyVersion}" == pin.original.ref
      else
        builtins.match "edge-[0-9]{8}-${builtins.substring 0 7 pin.locked.rev}" omarchyVersion != null;
  in
  assertMsg want "version-label: flake.nix:540 says omarchyVersion = \"${omarchyVersion}\", but flake.lock pins omarchy at ${
    pin.original.ref or pin.locked.rev
  }";
pkgs.runCommand "nixarchy-omarchy-version-label" { } "touch $out"
