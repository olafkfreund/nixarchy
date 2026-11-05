# shortcut: nixpkgs 1d060086 pins opencode 2.2.5's node_modules to the wrong hash, fixed upstream
# in c399e1b7fb. Matching only that hash, this stops applying on its own; delete this file and
# its callers once the pin has moved past that commit.
# Why: modules/AGENTS.md#opencode-hash-until-the-channel-catches-up
pkgs:
if
  pkgs.opencode.node_modules.outputHash or "" == "sha256-xfOVcw1+waLVNhFDwzOtzxrUSQEogvn88YomydOlhwc="
then
  pkgs.opencode.overrideAttrs (old: {
    node_modules = old.node_modules.overrideAttrs {
      outputHash = "sha256-prx9dX7kUvs/E3zopkaPk5LXh3xJAy5sZeum/W8L7cA=";
    };
  })
else
  pkgs.opencode
