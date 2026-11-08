{
  pkgs,
  omarchy,
  omarchySrc,
}:
let
  inputs = [
    pkgs.jq
    pkgs.bash
    pkgs.coreutils
    pkgs.diffutils
    pkgs.findutils
  ];
  common = {
    nativeBuildInputs = inputs;
    FIXTURE_A = ./fixtures/shell-json/v4.0.6.json;
    FIXTURE_C = "${omarchySrc}/config/omarchy/shell.json";
    MIGRATE_SCRIPT = "${omarchy}/bin/omarchy-migrate-user";
    ORACLE_SOURCE = omarchySrc;
    NIXARCHY_USER_MIGRATIONS = omarchy.passthru.userMigrations;
    # The oracle's migrations call omarchy-shell-config, which reads it under set -u.
    OMARCHY_PATH = "${omarchy}/share/omarchy";
  };
  # The sandbox has no /usr/bin/env: an unpatched stub fails to exec, ping never
  # answers, and the port exits 0 having migrated nothing.
  stubs = pkgs.runCommand "nixarchy-user-migrations-stubs" { } ''
    cp -r ${./user-migrations} $out
    chmod -R u+w $out
    patchShebangs $out
  '';
  path = "${stubs}:${omarchy}/bin:${pkgs.lib.makeBinPath inputs}";
  expectedA = pkgs.runCommand "nixarchy-user-migrations-expected-a" common ''
    export PATH=${path}:$PATH
    bash ${./user-migrations/run} expected
  '';
in
pkgs.runCommand "nixarchy-user-migrations"
  (
    common
    // {
      EXPECTED_A = expectedA;
      passthru.expectedA = expectedA;
    }
  )
  ''
    export PATH=${path}:$PATH
    bash ${./user-migrations/run} check
  ''
