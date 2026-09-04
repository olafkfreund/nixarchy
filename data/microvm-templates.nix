# The fifth catalogue -- and the odd one out among the other four. Every other
# catalogue in this directory describes something (an app, a service, a devenv
# preset) and something else turns the description into Nix. This one *is*
# Nix: `module` names a path this repo evaluates itself, into a NixOS closure,
# because a template has to be buildable for `nix build .#checks...` (the next
# issue, #224) to prove it boots without booting it.
#
# That is also why `module` is a path and not a `lines` string the way
# data/devenv-presets.nix's `lines` is. devenv.nix is never evaluated here --
# it is pasted into a file this repo will never see again, so a typo in it is
# invisible until `nixarchy dev init` builds the shell. A microvm template
# left as a string would carry the same blind spot into something we DO
# control, for no reason: nothing stops us from writing it as real Nix and
# having a check build it.
#
# ## The bar: a template is exactly a NixOS module
#
# The same bar data/devenv-presets.nix sets for itself, translated to this
# catalogue's material. Plain NixOS plus whatever microvm.nix's own options
# add -- no nixarchy vocabulary. The user who outgrows a template copies
# `module` into a flake of their own and grows it from the NixOS manual and
# microvm.nix's options reference, not from a page on this project.
#
# Two rules follow, and both exist to protect the closure rather than taste:
#
#   * Nothing in a template may depend on a per-VM value. flake.nix's
#     `lib.mkMicrovm` builds one runner per template, shared by every VM a
#     user ever names from it -- the name is a directory the runner is
#     `exec`'d inside, never a Nix argument (see modules/microvm/guest.nix for
#     how the guest learns its hostname without one). A template that read,
#     say, `builtins.getEnv "USER"` would make that promise false.
#   * Persistence is a `microvm.volumes` entry with a RELATIVE image path.
#     microvm.nix resolves it against the runner's working directory (see
#     lib/runners/qemu.nix in the pinned commit -- volumes become `-drive
#     file=${image}` with no path rewriting), which is what lets one closure
#     serve `~/.local/state/nixarchy/microvm/alice/` and
#     `~/.local/state/nixarchy/microvm/bob/` with two different disks.
#
# ## Fields
#   label    Shown by whatever names a template (the trigger.vm menu group in
#            #226; nothing reads this field yet).
#   module   A path to a NixOS module. Imported by `lib.mkMicrovm` in
#            flake.nix alongside modules/microvm/guest.nix, which is what
#            supplies everything a template does NOT have to: the shared
#            store, the host-directory share, user networking, autologin, and
#            the runtime hostname. A template imports nothing else nixarchy
#            ships -- see the bar above.
#   note     What the template gives you and what it costs, same job as the
#            `note` field in every other catalogue here.
#
{
  shell = {
    label = "Shell";
    module = ../modules/microvm/templates/shell.nix;
    note = "A bare NixOS shell with nothing added beyond modules/microvm/guest.nix -- the fastest way to a throwaway prompt, and the template every other one starts from.";
  };

  python = {
    label = "Python";
    module = ../modules/microvm/templates/python.nix;
    note = "python3 and uv, 3 GiB of RAM. Ephemeral like Shell -- run 'uv venv /mnt/host/.venv' if the venv should outlive the VM.";
  };

  podman = {
    label = "Podman";
    module = ../modules/microvm/templates/podman.nix;
    note = "Rootless-capable podman with Docker compatibility. /var/lib/containers is a 20 GiB volume that survives a restart; the rest of the root filesystem does not.";
  };

  persistent = {
    label = "Persistent";
    module = ../modules/microvm/templates/persistent.nix;
    note = "Shell, plus /home on a 10 GiB volume. The volume goes when the VM does ('nixarchy vm rm'); the root filesystem is still thrown away every boot.";
  };
}
