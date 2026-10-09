{ pkgs, ... }:
# gliff must find the Vulkan loader, and its client must find ssh.
#
# What this defends: ash dlopens libvulkan.so.1 by name, so the loader has to be
# on the RUNPATH of all three binaries. Without it gliff does not fail -- it
# falls back to the CPU tier, and every machine looks fine. The `gliff` client
# is wrapped, so the ELF to read is .gliff-wrapped. It also resolves `ssh` by
# name, so the wrapper has to put openssh on PATH.
#
# This is the only CI layer that sees it: the session VM runs gliff on the CPU
# tier anyway, and only real hardware (verify.sh) notices a lost GPU tier.
#
# The floor is the other half: a loop over binaries that were renamed or moved
# reads none and passes in silence, so fewer than three checked is a failure.
pkgs.runCommand "gliff-runpath" { nativeBuildInputs = [ pkgs.patchelf ]; } ''
  bin=${pkgs.gliff}/bin
  checked=0
  for b in gliff-server gliff-probe .gliff-wrapped; do
    rp=$(patchelf --print-rpath "$bin/$b")
    case ":$rp:" in
      *":${pkgs.vulkan-loader}/lib:"*) ;;
      *) echo "FAIL: $b RUNPATH lacks ${pkgs.vulkan-loader}/lib: $rp"; exit 1 ;;
    esac
    checked=$((checked + 1))
  done
  [ "$checked" -ge 3 ] || { echo "FAIL: only $checked binaries checked"; exit 1; }

  grep -q '${pkgs.openssh}/bin' "$bin/gliff" \
    || { echo "FAIL: gliff wrapper does not put ${pkgs.openssh}/bin on PATH"; exit 1; }
  touch $out
''
