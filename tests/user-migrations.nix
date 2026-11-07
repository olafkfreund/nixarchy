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
  ];
  common = {
    nativeBuildInputs = inputs;
    FIXTURE_A = ./fixtures/shell-json/v4.0.6.json;
    FIXTURE_C = "${omarchySrc}/config/omarchy/shell.json";
    MIGRATE_SCRIPT = "${omarchy}/bin/omarchy-migrate-user";
    ORACLE_SOURCE = omarchySrc;
  };
  path = "${./user-migrations}:${omarchy}/bin:${pkgs.lib.makeBinPath inputs}";
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
