# The auto-fix table for .github/scripts/pin-fix.sh (#1459), keyed by root
# flake input name. When a nixpkgs bump breaks evaluation, an input is a
# candidate for a proposed move to its upstream default branch if its `probe`
# target is among the targets that fail. `probe` is an installable without the
# leading `.#`; tests/pin-fix.nix asserts each one exists in this flake.
{
  microvm = {
    # One representative runner: a broken pin fails all 18 identically.
    probe = "microvm-agent";
    why = "every .#microvm-* runner evaluates through it";
  };
  sops-nix = {
    probe = "checks.x86_64-linux.sops-evaluates";
    why = "vm-toplevel does not reach it (#1030), so the check that does is the probe";
  };
  mcp-servers-nix = {
    probe = "checks.x86_64-linux.vm-toplevel";
    why = "vm-toplevel and reference-toplevel both evaluate it";
  };
  zen-browser = {
    probe = "zen-browser";
    why = "the package itself (flake.nix re-exports zen-browser.packages.default)";
  };
}
