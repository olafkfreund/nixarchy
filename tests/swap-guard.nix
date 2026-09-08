{ inputs, pkgs, ... }:
# An installed machine has some swap, and can still refuse it.
#
# What this defends: installer/disk-config.nix lays down @, @home, @nix, @log
# and the snapshot subvolumes and NO swap of any kind -- no partition, no file,
# no zram. A tester asked why they had none, which is the right question.
#
# The cost is not theoretical. modules/nixos.nix enables systemd-oomd and gives
# its slices ManagedOOMSwap=kill -- a policy about swap pressure, on a system
# where swap pressure cannot occur. It falls back to memory pressure, which
# fires later and kills more. And a nixos-rebuild over a large closure is
# exactly the workload that wants to page out something idle and cannot.
#
# Evaluation and not a VM, deliberately: whether a machine HAS swap is a
# configuration fact, and the install checks would each need a memory-pressure
# workload to observe it. checks.install would pass on a swapless machine
# forever, because installing does not need swap -- rebuilding later does.
let
  inherit (inputs.self.nixosConfigurations) reference iso;

  # A machine that has real swap already, or hibernates, must be able to say
  # so. mkDefault is what makes that one line rather than an mkForce.
  overridden = reference.extendModules {
    modules = [ { zramSwap.enable = false; } ];
  };

  b = v: if v then "true" else "false";
in
pkgs.runCommand "nixarchy-swap-guard" { } ''
  fail=0
  check() { # check <name> <actual> <wanted>
    if [ "$2" = "$3" ]; then echo "  ok      $1"
    else echo "  FAILED  $1: got $2, wanted $3"; fail=1; fi
  }

  check "an installed machine has swap" \
    ${b reference.config.zramSwap.enable} true

  # The one that keeps this honest. An adopter with a real swap partition, or
  # one who hibernates, must not have zram forced on them -- and a check that
  # only asserted the value would pass on an mkForce that takes the choice
  # away.
  check "and can turn it off in one line" \
    ${b overridden.config.zramSwap.enable} false

  # NOT the live ISO, and that is not an oversight. The module's config sits
  # behind mkIf cfg.enable and the ISO is an installer, not a nixarchy desktop
  # -- nixpkgs' own default is the only definition there. Asserted so that if
  # it ever changes, it changes on purpose.
  check "the live ISO is unaffected" \
    ${b iso.config.zramSwap.enable} false

  # zram is not hibernation, and the docs must not imply it is. Suspend-to-disk
  # needs real swap at least the size of RAM; zram is in RAM and cannot provide
  # it. This asserts the manual says so, because the wrong belief here is
  # discovered by closing a laptop lid and losing a session.
  grep -q 'hibernat' ${../docs/manual/troubleshooting.md} || {
    echo "  FAILED  the manual no longer explains that zram is not hibernation" >&2
    exit 1
  }
  echo "  ok      and the manual says it is not hibernation"

  [ "$fail" = 0 ] || exit 1
  echo "an installed machine has swap, and can still refuse it"
  touch $out
''
