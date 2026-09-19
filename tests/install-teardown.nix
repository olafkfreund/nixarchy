{ pkgs }:
let
  wrapper = pkgs.writeText "install-teardown-wrapper.py" (
    import ./with-vm-cleanup.nix pkgs.lib ''
      machine = create_owned_machine("qemu", name="fixture")
      raise AssertionError("ORIGINAL INSTALL ASSERTION")
    ''
  );
in
pkgs.runCommand "nixarchy-install-teardown"
  {
    nativeBuildInputs = [ pkgs.python3Minimal ];
    VM_CLEANUP_WRAPPER = wrapper;
  }
  ''
    python3 ${./.}/install-teardown.py
    touch "$out"
  ''
