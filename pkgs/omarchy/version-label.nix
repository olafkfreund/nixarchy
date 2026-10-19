# #1371: the Omarchy commit nixarchy pins keeps its release/edge label; any
# other commit (the dev channel, or an override) is named after itself.
{
  version,
  pinnedRev,
  input,
}:
let
  rev = input.rev or null;
  date = builtins.substring 0 8 (input.lastModifiedDate or "unknown");
  short = input.shortRev or "unknown";
in
if rev != null && rev == pinnedRev then version else "dev-${date}-${short}"
