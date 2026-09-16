#!/usr/bin/env bash
# Which checks no other job claims -- the targets build.yml's omarchy job
# builds, and the set the nightly keeps proofs alive for (#728).
#
#   generated-checks.sh              the targets, one flake installable per line
#   generated-checks.sh names        every check in the flake
#   generated-checks.sh claimed      the opt-out list
#   generated-checks.sh exempt       built under another attribute
#   generated-checks.sh nightly-only claimed, and deliberately not PR-gated
#
# Lived inline in build.yml until #728 needed the same set in nightly.yml. A
# second copy there is the failure AGENTS.md section 4 names -- a hand-maintained
# list fails OPEN -- so there is one derivation and two callers.
set -uo pipefail

system=${NIXARCHY_SYSTEM:-x86_64-linux}

# WHO claims each check, rather than "is it named anywhere".
#
# This list is the opt-OUT. Everything not on it is built by the generated
# step, which derives its targets from the flake -- so adding a check now runs
# it, with no YAML to write and nothing to forget. That inversion is the point:
# `checks.<name> is defined but no workflow runs it` fired four times in one
# day, every time because a check was added and a step was not, and the gate
# can only ever report that after the fact.
#
# These are the checks another job runs for a reason the generated step cannot
# satisfy -- a bigger runner, KVM, a 90-minute budget, a disk-free step, or a
# Hyprland closure that wants its own concurrency group. Naming them here is a
# claim that is CHECKED by build.yml in both directions, so the list cannot rot
# into fiction.
#
# wifi-hwsim is a nixosTest and needs /dev/kvm. The generated step runs in the
# omarchy job, which has no KVM setup -- the udev rule lives in `box` -- so
# leaving it generated put a VM test in a job that cannot boot one. The
# integration that added the check is what surfaced it.
claimed="wifi-hwsim install free-space installer-refusal
  install-encrypted install-iso install-iso-net iso-budget microvm-boot
  reinstall-vm
  box-boot box-template coexist dashboard-clock installer-ui
  installer-wizard integration microvm-template options plugin
  reference-toplevel session try-nixarchy vm-toplevel"

# Two are covered by a path the grep in build.yml cannot see, and are listed
# here rather than left to look accidental:
#   omarchy                        built as `nix build .#omarchy`
#   reference-unencrypted-toplevel pulled in by checks.install
#   omarchy-runtime                built as `nix build .#omarchy-runtime`
# (omarchy-runtime is the same derivation either way -- the checks entry is an
# `inherit` of the package, so building the package IS building the check.)
exempt="omarchy omarchy-runtime reference-unencrypted-toplevel"

# Claimed, and deliberately NOT gated on pull requests. "Some workflow names
# it" was never the whole question (#164): a check named only by nightly.yml
# satisfies that grep and still gates nothing, because nothing it can catch
# arrives before the merge. That is #144 -- the install check sat in exactly
# this position for most of this repo's life, and #123 shipped straight through
# it, green.
#
# These stay there deliberately, and the cost is the reason:
#   install-iso  builds a 6 GB image and installs it -- ~3h
#   iso-budget   measures that same image, so pays the same build
#   install-iso-net  the same image build plus a closure fetch
#   install-encrypted  an install-class VM with the same 85-minute driver
#                    budget as checks.install; install-check.yml already runs
#                    two of those against a 90-minute job and that pair grazed
#                    the timeout on 2026-09-03
#   microvm-boot     a nested VM on the -tcg runner
# reinstall-vm builds a SECOND full ISO and installs from it -- the same ~3h
# shape as install-iso, and it arrived on main (#512) before it was claimed
# here, which would have put a multi-hour build in the light job on every pull
# request.
#
# It is also the list a keep-alive must never rebuild: a nightly that rebuilt
# install-iso to refresh a proof would spend three hours doing it.
nightly_only="install-iso iso-budget microvm-boot install-iso-net install-encrypted reinstall-vm"

# Collapsed to single spaces before anything tests membership.
# `case " $claimed " in *" $c "*)` wants a space on BOTH sides, and the lists
# above are written across lines for readability -- so the last name on every
# line was followed by a newline and matched nothing. Four checks
# (installer-refusal, microvm-boot, installer-ui, plugin) were silently added
# to the generated set while another job already built them, and only the count
# not adding up showed it: 24 generated + 22 claimed against 45 checks.
claimed=$(printf '%s' "$claimed" | tr -s ' \n' ' ')
exempt=$(printf '%s' "$exempt" | tr -s ' \n' ' ')
nightly_only=$(printf '%s' "$nightly_only" | tr -s ' \n' ' ')

names() {
  # Ask Nix, do not parse the file.
  #
  # This used to be an awk range plus `grep -oE '^        [a-z]...'` -- EIGHT
  # spaces of indentation. #299 added a `let ... in` around the checks block,
  # every entry moved to TEN, and the grep silently matched nothing from that
  # commit onward: the guard printed its success line having extracted zero
  # names.
  #
  # A guard that reads the source's LAYOUT rather than its VALUE fails this
  # way. `nix eval` cannot go stale when someone adds a binding.
  local n
  n=$(nix eval --raw ".#checks.$system" \
    --apply 'c: builtins.concatStringsSep "\n" (builtins.attrNames c)') || return 1

  # 20 is well under the current count and well over zero -- it catches
  # "extracted nothing" without needing maintenance every time a check is added
  # or removed.
  local count
  count=$(printf '%s\n' "$n" | grep -c . || true)
  if [ "${count:-0}" -lt 20 ]; then
    echo "::error::the check list came back with $count names, which is" \
      "too few to be real -- this guard is not reading the flake" >&2
    return 1
  fi
  printf '%s\n' "$n"
}

case "${1:-generated}" in
  names) names ;;
  claimed) printf '%s\n' "$claimed" ;;
  exempt) printf '%s\n' "$exempt" ;;
  nightly-only) printf '%s\n' "$nightly_only" ;;
  generated)
    all=$(names) || exit 1
    for c in $all; do
      case " $claimed $exempt " in *" $c "*) continue ;; esac
      echo ".#checks.$system.$c"
    done
    ;;
  *)
    echo "generated-checks.sh: unknown argument '$1'" >&2
    exit 2
    ;;
esac
