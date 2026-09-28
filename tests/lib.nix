# Helpers the checks share; not a check itself (tests/test-registration.nix
# exempts it). `inputs` is optional: okBad needs nothing, vmPackage needs the
# flake.
{
  inputs ? null,
}:
{
  # The vm's copy of a package, by pname. The system is evaluated, not built.
  vmPackage =
    name:
    builtins.head (
      builtins.filter (
        p: (p.pname or p.name or "") == name
      ) inputs.self.nixosConfigurations.vm.config.environment.systemPackages
    );

  # Pass/fail printers; the script initialises `fails=0`. No trailing newline,
  # so `''${okBad}` on its own line yields exactly the two lines it replaces.
  okBad = "ok() { echo \"  ok      $1\"; }\nbad() { echo \"  FAILED  $1\"; fails=$((fails + 1)); }";
}
