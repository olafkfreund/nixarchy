# Checks whose output must follow the source commit.
# flake.nix and .github/scripts/commit-independent.sh read this table.
{
  vm-toplevel = "self.nixosConfigurations: the machine a user gets";
  reference-toplevel = "self.nixosConfigurations: the machine a user gets";
  reference-unencrypted-toplevel = "self.nixosConfigurations: the machine a user gets";
  install = "installer/host.nix extraDependencies collects every input's outPath to seed what the installed machine evaluates";
  install-encrypted = "installer/host.nix extraDependencies collects every input's outPath to seed what the installed machine evaluates";
  free-space = "installer/host.nix extraDependencies collects every input's outPath to seed what the installed machine evaluates";
  installer-refusal = "installer/host.nix extraDependencies collects every input's outPath to seed what the installed machine evaluates";
  iso-source = "installer/cd.nix inputSources collects the source commit";
  iso-wifi = "installer/cd.nix inputSources collects the source commit";
  iso-budget = "installer/cd.nix inputSources collects the source commit";
  install-iso-net = "installer/cd.nix inputSources collects the source commit";
  installer-lock = "installer/mkFlake.nix:22 pins self.rev";
  nixarchy-options = "tests/nixarchy-options.nix asserts the real rev";
  options-files = "vm/configuration.nix:173 writes path:''${inputs.self} into the VM's generated flake (owner, 2026-11-08: evaluation only, so it stays commit-bound)";
  cache-keys = "hashes the whole source tree by design (owner, 2026-11-08: evaluation only, so it stays commit-bound)";
}
