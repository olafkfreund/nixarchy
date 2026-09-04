inputs:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.nixarchy;
  apps = import ../data/apps.nix;

  # The command each app puts on PATH, so the menu can tell "you already have
  # this" from "you have not installed it".
  #
  # meta.mainProgram rather than the attribute name: it is right where the two
  # differ, and they differ often -- obs-studio puts `obs` on PATH, not
  # `obs-studio`. It is metadata, so this reads it without building anything.
  #
  # tryEval because an unfree package throws at *evaluation* when allowUnfree
  # is off, and spotify and obsidian are both unfree. Without it, adding this
  # would have broken evaluation for everyone who has not opted into unfree --
  # a far worse outcome than the dim row it is here to draw. Falling back to
  # the app's own name is the same guess omarchy-pkg-present already makes.
  appBinary =
    name: app:
    let
      path = lib.splitString "." (app.attr or name);
      probe = builtins.tryEval (
        let
          p = lib.attrByPath path null pkgs;
        in
        if p == null then null else (p.meta.mainProgram or null)
      );
    in
    if probe.success && probe.value != null then probe.value else name;

  available = lib.filterAttrs (_: a: !(a ? unavailable)) apps;
  unavailable = lib.filterAttrs (_: a: a ? unavailable) apps;

  # One submodule per app. `settings` only has somewhere to go when the app is
  # a NixOS module rather than a bare package, so it is only offered there --
  # a freeform attrset with no target is a trap, not a feature.
  appModule =
    name: app:
    {
      enable = lib.mkEnableOption "${app.label} (${app.category})";

      # No `extraConfig` option here on purpose. The file the template is
      # written to is itself a NixOS module, so arbitrary configuration can
      # sit directly beside the app selection -- strictly more capable than
      # an option, and without forcing the module system to read a freeform
      # attrset's structure to learn what this module defines, which is a
      # dependency cycle.
    }
    // lib.optionalAttrs (app ? attr) {
      package = lib.mkOption {
        type = lib.types.package;
        # `ours` apps are ones nixpkgs does not carry and that nixarchy
        # packages itself; they live in the overlay's nixarchy-apps set.
        default =
          if app.ours or false then
            inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.${app.attr}
          else
            pkgs.${app.attr};
        defaultText = lib.literalExpression (
          if app.ours or false then "nixarchy.packages.\${system}.${app.attr}" else "pkgs.${app.attr}"
        );
        description = "Package used for ${app.label}. Override to pin or patch it.";
      };
    }
    // lib.optionalAttrs (app ? option) {
      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        example = lib.literalExpression (
          if name == "tailscale" then ''{ useRoutingFeatures = "client"; }'' else "{ }"
        );
        description = ''
          Merged into `${lib.concatStringsSep "." app.option}`. ${app.note or ""}
        '';
      };
    };

  # Every definition below is emitted for EVERY app, with mkIf deferring the
  # condition. Filtering by `enable` first would make the set of attributes
  # this module defines depend on config -- and the module system has to know
  # which options a module defines in order to evaluate those options, so that
  # is a cycle. Static structure, lazy values.
  appModuleConfig = lib.mkMerge (
    lib.mapAttrsToList (
      name: app:
      lib.optionalAttrs (app ? option) (
        lib.mkIf cfg.apps.${name}.enable (
          lib.setAttrByPath app.option ({ enable = true; } // cfg.apps.${name}.settings)
        )
      )
    ) available
  );

  # A value, not a structure, so this one may read config freely.
  appPackages = lib.concatLists (
    lib.mapAttrsToList (
      name: app: lib.optional ((app ? attr) && cfg.apps.${name}.enable) cfg.apps.${name}.package
    ) available
  );

  needsUnfree = lib.any (name: (available.${name}.unfree or false) && cfg.apps.${name}.enable) (
    lib.attrNames available
  );

  # ── The template ────────────────────────────────────────────────────────
  # Written fully populated and fully commented out, so enabling an app is
  # uncommenting one line rather than knowing a nixpkgs attribute. The `#@ id`
  # marker on each line is what nixarchy-app-enable matches on: it survives the
  # user reformatting, reordering or annotating the file, which a line-number
  # or label match would not.
  categories = lib.unique (map (a: a.category) (lib.attrValues apps));

  templateRow =
    name: app:
    let
      notes = lib.filter (s: s != "") [
        (lib.optionalString (app.unfree or false) "unfree")
        # Collapsed to one line: a note with a newline in it would break out
        # of the `#` comment and make the generated file fail to parse.
        (lib.replaceStrings [ "\n" ] [ " " ] (app.note or ""))
      ];
      suffix = lib.optionalString (notes != [ ]) "  # ${lib.concatStringsSep " — " notes}";
    in
    "    # ${name}.enable = true;  #@ ${name}${suffix}\n"
    + lib.optionalString (app ? option) "    #   ${name}.settings = { };  #@ ${name}.settings\n";

  templateCategory =
    cat:
    let
      inCat = lib.filterAttrs (_: a: a.category == cat) available;
      rows = lib.concatStrings (lib.mapAttrsToList templateRow inCat);
    in
    lib.optionalString (inCat != { }) ''

        # ── ${cat} ${lib.concatStrings (lib.genList (_: "─") (60 - lib.stringLength cat))}
      ${rows}'';

  unavailableNote = lib.concatStrings (
    lib.mapAttrsToList (_: a: "#   ${a.label} — ${a.unavailable}\n") unavailable
  );

  # Every nixpkgs attribute the curated list already covers, mapped back to
  # its app id. nixarchy-pkg-add checks this first: typing `firefox` should
  # get you `nixarchy-app-enable firefox`, which sets programs.firefox and
  # brings policies and extensions with it, not a bare package in
  # systemPackages that does none of that. Both the app id and its attribute
  # are listed, because either is a plausible thing to type.
  appAttrTable = pkgs.writeText "nixarchy-app-attrs.tsv" (
    lib.concatStrings (
      lib.mapAttrsToList (
        name: app:
        lib.concatMapStrings (key: "${key}\t${name}\n") (
          lib.unique ([ name ] ++ lib.optional (app ? attr) app.attr)
        )
      ) available
    )
  );

  # The curated list as search rows: id, label, category, note. Notes are
  # flattened because the index this feeds is tab-separated and a note with a
  # newline in it would silently become three broken rows -- the same reason
  # templateRow collapses them.
  # The NixOS option index, or "" when this system has no manual to take it
  # from. `system.build.manual` is defined under documentation.nixos.enable,
  # which is on by default but off in every NixOS test node -- so a hard
  # reference here evaluates fine on a real machine and fails the session
  # check, which is exactly how it got through review.
  #
  # Built rather than fetched, but built by nixpkgs: it substitutes from
  # cache.nixos.org, so it costs a 2.6 MiB download rather than an evaluation
  # of every option on the machine.
  optionsJsonPath =
    let
      manual = config.system.build.manual.optionsJSON or null;
    in
    if manual == null then "" else "${manual}/share/doc/nixos/options.json";

  appIndexTable = pkgs.writeText "nixarchy-app-index.tsv" (
    lib.concatStrings (
      lib.mapAttrsToList (
        name: app:
        let
          flat = lib.replaceStrings [ "\n" "\t" ] [ " " " " ];
        in
        "${name}\t${app.label}\t${app.category}\t${flat (app.note or "")}\n"
      ) available
    )
  );

  # The catalogue from data/services.nix, as commented-out lines.
  #
  # Two shapes, because the catalogue has two kinds and the difference is the
  # whole point. A "bundled" entry writes the nixarchy option, because nixarchy
  # does something upstream does not. A "plain" entry writes the REAL upstream
  # line -- `services.openssh.enable = true;` -- because there is nothing to
  # add, and a nixarchy alias for a one-line toggle would only be a second
  # vocabulary to unlearn the moment they read anyone else's configuration.
  serviceCatalogue = import ../data/services.nix;
  flatpakCatalogue = import ../data/flatpaks.nix;

  # Flatpaks go in services.nix rather than a fourth file.
  #
  # They are applications, so apps.nix is the tempting home -- and the wrong
  # one: that file's header promises "Applications available through the
  # Omarchy menu, as NixOS configuration", meaning software from nixpkgs with
  # everything that implies. A flatpak is a different tier with weaker
  # promises, and mixing the two would make the file quietly dishonest.
  #
  # services.nix already holds things that are decisions about the machine
  # rather than packages, which is what enabling a flatpak is: it turns on a
  # daemon, adds a remote, and installs software the store does not hold.
  # Curated flatpaks as picker rows, plus the one row that reaches the rest of
  # Flathub. Written whole in Nix rather than transformed by awk at index time
  # like the app rows: there are a handful of these and the preview text is
  # prose, so a template is clearer than a transformation.
  #
  # Five tab-separated fields, matching every other source: kind, name,
  # summary, option type (unused here), preview.
  flatpakIndexRows = pkgs.writeText "nixarchy-flatpak-rows.tsv" (
    lib.concatStrings (
      lib.mapAttrsToList (name: fp: ''
        flatpak	${name}	${fp.label} -- flatpak, from ${
          if fp ? remote then fp.remote.name else "Flathub"
        }		FLATPAK  ${name}\n\n${fp.label}\n${fp.note}\n\nDeclared, not reproducible: the id travels to your next machine, the version does not. Enabling this writes a line in your services selection:\n  programs.nixarchy.flatpaks.apps.${name}.enable = true;
      '') flatpakCatalogue
    )
    # The way out of the catalogue. A row rather than a flag, because a flag
    # nobody knows about is not a search anyone finds -- and this is precisely
    # the row someone needs when the other three sources have failed them.
    # Escaped \n, not a real one: the preview field keeps its newlines escaped
    # like every other source, because the whole row must stay on ONE line. A
    # real newline splits this into five rows, four of them nonsense, and the
    # picker renders them without complaint.
    + "flatpak	flathub	Search all of Flathub for something not listed here (needs a network)		"
    + "SEARCH FLATHUB\\n\\nAsks flathub.org for anything, not just what nixarchy curates.\\n\\n"
    + "This is the only row here that needs a network, and the only one that can offer an app nobody has checked. A hit that is in nixarchy's catalogue is enabled the normal way; anything else prints a line for you to paste, because writing an unchecked app id into your configuration is not this tool's call to make.\n"
  );

  flatpakRow =
    name: fp:
    let
      remote = lib.optionalString (fp ? remote) " — from ${fp.remote.name}, not Flathub";
    in
    "    # programs.nixarchy.flatpaks.apps.${name}.enable = true;  #@ ${name}"
    + "  # ${fp.note}${remote}\n";

  flatpakBlock = lib.optionalString (flatpakCatalogue != { }) (
    "    # ── Flatpak ──────────────────────────────────────\n"
    + "    #\n"
    + "    # Declared, not reproducible: the ids below travel to your next\n"
    + "    # machine, the versions do not. A rollback restores this list, not\n"
    + "    # the software that was installed from it, and the first switch\n"
    + "    # after enabling one needs a network.\n"
    + "    #\n"
    + "    # Their data in ~/.var/app is yours and nixarchy never touches\n"
    + "    # it: turning one off here removes the app, not what you did\n"
    + "    # with it.\n"
    + lib.concatStrings (lib.mapAttrsToList flatpakRow flatpakCatalogue)
    + "\n"
  );

  serviceRow =
    name: svc:
    let
      suffix = if svc ? note then "  # ${svc.note}" else "";
      line =
        if svc.kind == "bundled" then
          "programs.nixarchy.services.${name}.enable = true;"
        else
          "${lib.concatStringsSep "." svc.option}.${svc.optionAttr or "enable"} = true;";
    in
    "    # ${line}  #@ ${name}${suffix}\n";

  serviceCategories = lib.unique (map (s: s.category) (lib.attrValues serviceCatalogue));

  serviceCategoryBlock =
    category:
    let
      rows = lib.filterAttrs (_: s: s.category == category) serviceCatalogue;
      # A fixed rule rather than one padded to a column: the box-drawing
      # character is three bytes and fixedWidthString counts bytes, so the
      # arithmetic that looks right produces a negative width.
      header = "    # ── ${category} ──────────────────────────────────────\n";
    in
    header + lib.concatStrings (lib.mapAttrsToList serviceRow rows) + "\n";

  servicesTemplate = pkgs.writeText "nixarchy-services.nix" ''
    # Services and system settings, as NixOS configuration.
    #
    # The companion to apps.nix. An app is a package; a service is a decision
    # about the machine. Uncomment what you want -- or pick it from the menu --
    # then run
    #
    #     nixarchy-apply
    #
    # Two kinds of line appear below and the difference is deliberate:
    #
    #   programs.nixarchy.services.X   nixarchy bundles several options here,
    #                                  because turning the thing on usefully
    #                                  takes more than one.
    #
    #   services.X.enable              the real NixOS option, because there was
    #                                  nothing for nixarchy to add. This is the
    #                                  line every wiki page will show you, and
    #                                  it is the same line here.
    #
    # This file is a NixOS module and nothing stops you writing any option in
    # it. Upstream's own settings work alongside ours -- if you enable
    # syncthing below, `services.syncthing.settings.folders` still does what
    # its documentation says.
    #
    # This file is yours. Nothing regenerates or overwrites it once created;
    # the current full list is always at /etc/nixarchy/services-template.nix.
    { ... }:
    {
    ${lib.concatStrings (map serviceCategoryBlock serviceCategories)}${flatpakBlock}}
  '';

  # No catalogue, on purpose.
  advancedTemplate = pkgs.writeText "nixarchy-advanced.nix" ''
    # Anything at all.
    #
    # apps.nix is a list nixarchy generated and services.nix is a catalogue it
    # curated. This file has neither, because at some point the answer to "how
    # do I do X on NixOS" is a NixOS option nobody put on a list, and a curated
    # desktop that has no room for that is a cage.
    #
    # It is an ordinary NixOS module. Every option in nixpkgs is available:
    #
    #   services.openssh.settings.PermitRootLogin = "no";
    #   boot.kernelParams = [ "quiet" ];
    #   users.users.you.extraGroups = [ "dialout" ];
    #
    # `nixarchy-search` writes here when you pick an option from it. Nothing
    # else touches this file.
    #
    # If you find yourself writing the same thing here on every machine, that
    # is worth an issue -- it probably belongs in the catalogue.
    { ... }:
    {
    }
  '';

  appsTemplate = pkgs.writeText "nixarchy-apps.nix" ''
    # Applications available through the Omarchy menu, as NixOS configuration.
    #
    # Every app is listed and every line is commented out. Uncomment what you
    # want -- or pick it from the menu, which uncomments it for you -- then run
    #
    #     nixarchy-apply
    #
    # to copy this into your flake and `nixos-rebuild switch`. Enable as many as
    # you like before applying; nothing is built until you do.
    #
    # This file is yours. Nothing regenerates or overwrites it once created;
    # the current full list is always at /etc/nixarchy/apps-template.nix.
    #
    # The `#@ name` markers are how the menu finds a line to uncomment. Keep
    # them and you can reformat, reorder and annotate this file freely.
    { ... }:
    {
      programs.nixarchy.apps = {
    ${lib.concatStrings (map templateCategory categories)}  };
    }

    # Offered by the Omarchy menu but with no nixpkgs equivalent:
    ${unavailableNote}'';
  # ── The menu defaults ───────────────────────────────────────────────────
  # Rewrites Omarchy's Install menu, in the DEFAULTS rather than in the user's
  # extension. Menu.qml reads two files and merges the second over the first:
  #
  #   defaults   $OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc
  #   user       ~/.config/omarchy/extensions/omarchy-menu.jsonc
  #
  # Nixarchy used to generate the second one and symlink it into /etc, which
  # put the port in the slot upstream documents as the user's -- and which
  # shell/plugins/README.md tells third-party plugins to write. A plugin's row,
  # or a row somebody typed, could not survive there, and nothing said so.
  #
  # But we build the package OMARCHY_PATH points at, so the defaults are ours
  # to write: `omarchyTree` below is that tree with this one file replaced.
  # Then the user's file is free, upstream's merge does the rest in the
  # direction it was designed for, and there is nothing to arbitrate. See #210.
  #
  # A failing `when:` hides a row outright (MenuModel.js isVisible); a
  # succeeding `disabled:` leaves it listed but dim and unselectable, which is
  # what upstream already uses for "you have this installed".
  # The override rows, as data. Deliberately WITHOUT label or icon: those are
  # copied from upstream's own menu at build time by the script below, so a
  # rename upstream follows through instead of being frozen into this repo.
  overrideSpec = pkgs.writeText "nixarchy-menu-overrides.json" (
    builtins.toJSON (
      {
        "install.package" = {
          # Upstream wears the Arch logo here; the generator would carry it
          # across untouched, since it only fills in what an override omits.
          icon = "󰉉";
          label = "Edit app selection";
          action = "omarchy-launch-editor $HOME/.config/nixarchy/apps.nix";
          description = "Every Omarchy app, as NixOS options";
        };
        # A new row, not an override: upstream has no equivalent because on
        # Arch there is nothing to search that pacman does not already answer.
        # The generator accepts an id upstream does not ship as long as the
        # override names the row itself, which is why label and icon are here.
        "install.search" = {
          icon = "󰍉";
          label = "Search";
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-search";
          description = "Every package, NixOS option and Omarchy app, in one picker";
        };

        # Every rebuild leaves the last one bootable and nothing said so.
        #
        # Under System because it is the system this restores. Upstream's
        # nearest equivalent is a snapper snapshot picked from the boot menu,
        # which is a different thing on NixOS: `@` here holds almost no
        # operating system, so a generation is what carries one. The snapshot
        # rows under Trigger cover the other half -- home, and service state
        # -- which no generation touches.
        "system.rollback" = {
          icon = "󰕍";
          label = "Roll back";
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-rollback";
          description = "Switch to an earlier system generation. Your home directory is not touched";
        };

        # Beside Roll back, because they are the two halves of the same
        # question: a generation brings this machine back on this disk, and a
        # pushed configuration brings it back on any other one.
        #
        # Reachable deliberately rather than only by notification. The command
        # existed for a while with no way to reach it except a nudge on a boot
        # you happened to act on, or knowing its name -- which meant the answer
        # to "I changed things, is that backed up?" was to remember a command.
        #
        # `when` rather than letting the row refuse when clicked: on a machine
        # nixarchy did not write, nixarchy-config-repo declines and explains
        # why, and a menu row whose only possible outcome is that explanation
        # is not worth drawing. /etc/nixarchy/managed is the same predicate the
        # command itself gates on -- see modules/nixos.nix.
        "system.backup" = {
          icon = "󰆔";
          label = "Back up configuration";
          when = "test -e /etc/nixarchy/managed";
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-config-repo";
          description = "Commit and push this machine's NixOS configuration, so a reinstall can bring it back";
        };

        # Snapshots under Trigger, beside the other "do a thing now" rows.
        #
        # Upstream's are taken by its updater and restored from the boot menu,
        # and neither happens here. These are new rows, so they carry their
        # own label and icon.
        "trigger.snapshot" = {
          icon = "󰆓";
          label = "Snapshot home";
          action = "omarchy-launch-floating-terminal-with-presentation omarchy-snapshot create";
          description = "Save your home directory as it is now. Instant, and costs nothing until files change";
        };

        "trigger.snapshot.restore" = {
          icon = "󰦛";
          label = "Restore from snapshot";
          action = "omarchy-launch-floating-terminal-with-presentation omarchy-snapshot restore";
          description = "Open an earlier version of your home directory and copy back what you want";
        };

        # The off-disk half, beside the on-disk one.
        #
        # A snapshot and a backup read as the same thing to someone who has
        # not lost a disk yet, so the two pairs sit together deliberately:
        # snapshots are instant and local, these two survive the hardware.
        # The descriptions are where that difference is actually said.
        #
        # `when` hides both rows on a machine nixarchy did not install --
        # the same gate the script itself enforces, so an imported
        # nixosModules.nixarchy is not offered a thing that will refuse.
        # A row that exists to say no is worse than no row.
        "trigger.home-backup" = {
          icon = "󰁯";
          label = "Back up desktop config";
          when = "nixarchy-home-backup --check";
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-home-backup";
          description = "Push your bar, keybindings and themes to a private git repository. Survives the disk";
        };

        "trigger.home-backup.restore" = {
          icon = "󰇚";
          label = "Restore desktop config";
          when = "nixarchy-home-backup --check";
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-home-backup restore";
          description = "Copy your bar, keybindings and themes back out of the backup. Works on a new machine";
        };

        "install.aur" = {
          when = "false";
        };

        # Upstream wears the Arch logo here and runs `pacman -Rns` on the
        # selection. This picks over the app selection instead, and only ever
        # edits ~/.config/nixarchy/apps.nix -- never the user's own NixOS
        # configuration, which nixarchy does not own.
        "remove.package" = {
          icon = "󰭌";
          label = "App";
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-app-remove";
          description = "Deselect apps, then Apply changes to rebuild without them";
        };

        # Upstream's label is "Omarchy" and its action pulls a git checkout and
        # runs pacman. The action is already replaced (see pkgs/omarchy/nix-bin);
        # this is the label catching up with what it now does.
        "update.omarchy" = {
          icon = "󰭌";
          label = "Nixarchy";
          description = "nh os switch --update: move every flake input forward, then rebuild";
        };

        # Omarchy's release channels are a pacman repository choice. Here the
        # version is whatever the flake's omarchy input is pinned to, so there
        # is nothing to switch. Switching nixpkgs between stable and unstable
        # would mean editing the user's own system flake, which nixarchy does
        # not own -- it owns the Omarchy installation and its applications.
        #
        # The children are hidden individually: hiding a parent keeps its rows
        # out of the menu tree, but they stay reachable through search and
        # `omarchy menu summon`.
        "update.channel" = {
          when = "false";
        };
        "update.channel.stable" = {
          when = "false";
        };
        "update.channel.rc" = {
          when = "false";
        };
        "update.channel.edge" = {
          when = "false";
        };
        "update.channel.dev" = {
          when = "false";
        };

        # The Arch wiki is the wrong manual on a NixOS host. All three wear
        # nf-linux-nixos (U+F1105), the snowflake -- the icon and label are
        # stated explicitly because the generator only carries upstream's
        # across when an override does not bring its own.
        "learn.arch" = {
          icon = "󱄅";
          label = "NixOS";
          action = "omarchy-launch-webapp 'https://wiki.nixos.org/'";
          description = "NixOS Wiki";
        };
        "learn.nixpkgs" = {
          icon = "󱄅";
          label = "Nixpkgs";
          action = "omarchy-launch-webapp 'https://search.nixos.org/packages'";
          description = "Search for a package";
        };
        "learn.nix-options" = {
          icon = "󱄅";
          label = "NixOS Options";
          action = "omarchy-launch-webapp 'https://search.nixos.org/options'";
          description = "Search NixOS configuration options";
        };
        "install.apply" = {
          icon = "";
          label = "Apply changes";
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-apply";
          description = "Copy the selection into your flake and nixos-rebuild switch";
        };
      }
      // lib.listToAttrs (
        lib.mapAttrsToList (
          name: app:
          lib.nameValuePair app.menuId (
            if app ? unavailable then
              {
                disabled = "true";
                description = "Not available on NixOS — ${app.unavailable}";
              }
            else
              {
                action = "nixarchy-app-enable ${name}";
                # Dim when the app is in the selection *or* already on PATH.
                #
                # The second half is the case nixarchy could not see before: an
                # app the user installed themselves, in their own
                # systemPackages or home.packages, which the selection knows
                # nothing about. The row offered to install something they
                # already had, and taking it would have written a second
                # declaration for it.
                #
                # Remove rows deliberately do NOT gain this. They stay bound to
                # the selection, because deselecting is the only removal
                # nixarchy is allowed to perform -- an app that arrived from
                # the user's own configuration is not this menu's to take away.
                disabled =
                  "grep -qE '^[[:space:]]*${name}\\.enable' $HOME/.config/nixarchy/apps.nix"
                  + " || command -v ${appBinary name app} >/dev/null 2>&1";
                description = "Enable in ~/.config/nixarchy/apps.nix, then Apply changes";
              }
          )
        ) (lib.filterAttrs (_: a: a ? menuId) apps)
      )
      # The services catalogue, as menu rows.
      #
      # Most of these are ids upstream does not ship -- Omarchy's menu has no
      # "turn on SSH" row because on Arch that is not a menu's business. The
      # generator takes a new id as long as the override names the row itself,
      # which is why label and icon are here; install.search arrived the same
      # way. Where upstream DOES have a row, the catalogue entry carries its
      # menuId and this overrides it in place -- tailscale is that case, and
      # carrying the id across is what keeps the generator from failing on a
      # row nothing maps.
      // lib.listToAttrs (
        lib.mapAttrsToList (
          name: fp:
          lib.nameValuePair "install.flatpak.${name}" {
            icon = "󰏓";
            inherit (fp) label;
            action = "nixarchy-service-enable ${name}";
            disabled = "grep -qE '^[[:space:]]*[^#[:space:]].*#@ ${name}([[:space:]]|$)' $HOME/.config/nixarchy/services.nix";
            description = "Flatpak — declared in your configuration, but updated by Flathub rather than by a rebuild";
          }
        ) flatpakCatalogue
      )
      // lib.listToAttrs (
        lib.mapAttrsToList (
          name: svc:
          lib.nameValuePair (svc.menuId or "install.service.${name}") {
            icon = svc.icon or "󰒓";
            inherit (svc) label;
            action = "nixarchy-service-enable ${name}";
            # Dim when the marked line is live, which is the same question
            # nixarchy-service-enable asks. Not the app rows' test: a plain
            # entry's line begins with services.openssh, not with the id, so
            # matching on the id would never fire.
            disabled = "grep -qE '^[[:space:]]*[^#[:space:]].*#@ ${name}([[:space:]]|$)' $HOME/.config/nixarchy/services.nix";
            description = svc.note;
          }
        ) serviceCatalogue
      )
      // cfg.menu.extraEntries
    )
  );

  # arch package name -> our app id. The generator uses this to find upstream's
  # remove.* rows, which identify their app by `omarchy-pkg-present <arch>` in
  # their `when`, and rewrite them to disable the app in the selection instead.
  archMap = pkgs.writeText "nixarchy-arch-map.json" (
    builtins.toJSON (
      lib.listToAttrs (
        lib.mapAttrsToList (name: app: lib.nameValuePair app.arch name) (
          lib.filterAttrs (_: a: a ? arch) available
        )
      )
    )
  );

  # Built with a script rather than string-concatenated in Nix, because it has
  # to read upstream's menu to carry each row's label and icon across.
  #
  # This is not cosmetic. MenuModel.js normalizes every entry before merging --
  # `label: value.label || id` and `icon: value.icon || ""` -- and then copies
  # ALL keys of the override over the default. So an override that omits a
  # label does not inherit upstream's; it replaces it with the raw id, and the
  # menu renders "install.ai.chatgpt" instead of "ChatGPT Desktop".
  menuDefaults =
    pkgs.runCommand "nixarchy-omarchy-menu.jsonc"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        inherit overrideSpec archMap;
        upstreamMenu = "${cfg.package}/share/omarchy/default/omarchy/omarchy-menu.jsonc";
      }
      ''
        python3 - "$upstreamMenu" "$overrideSpec" "$archMap" "$out" <<'PY'
        import json, re, sys

        upstream_path, spec_path, archmap_path, out_path = sys.argv[1:5]

        def strip_jsonc(raw):
            # The same two transformations MenuModel.js applies.
            raw = re.sub(r"^\s*//[^\n]*(\n|$)", "", raw, flags=re.M)
            return re.sub(r",(\s*[}\]])", r"\1", raw)

        upstream = json.loads(strip_jsonc(open(upstream_path).read()))
        overrides = json.load(open(spec_path))
        arch_map = json.load(open(archmap_path))

        # Upstream's remove.* rows name their app only in their `when`, as
        # `omarchy-pkg-present <arch-package>`. Deriving the overrides from
        # that keeps them tracking upstream instead of being hand-listed here,
        # and means a row upstream adds is picked up on the next bump.
        for row_id, row in upstream.items():
            if not row_id.startswith("remove.") or row_id in overrides:
                continue
            m = re.search(r"omarchy-pkg-present\s+([a-z0-9._@+-]+)", str(row.get("when", "")))
            if not m:
                continue
            app = arch_map.get(m.group(1))
            if not app:
                continue
            overrides[row_id] = {
                "action": f"nixarchy-app-disable {app}",
                # Show the row only when the app is actually selected, which is
                # what upstream's `omarchy-pkg-present` meant.
                "when": (
                    "grep -qE '^[[:space:]]*" + app
                    + "\\.enable' $HOME/.config/nixarchy/apps.nix"
                ),
                "description": "Remove from your app selection, then Apply changes",
            }

        out = {}
        missing = []
        for row_id, override in overrides.items():
            base = upstream.get(row_id)
            if base is None and not {"label", "icon"} & set(override):
                # A row we target that upstream no longer ships, and we have no
                # name of our own for it -- worth failing on rather than
                # rendering a raw id in the menu.
                missing.append(row_id)
                continue
            merged = dict(override)
            # Carry across EVERY key the override does not state. MenuModel.js
            # normalizes an entry before merging -- label falls back to the id,
            # and every other field to "" -- and then copies all of the
            # override's keys over the default. So an override that omits a
            # key does not inherit upstream's, it blanks it: omitting `label`
            # renders the raw id, and omitting `action` makes the row do
            # nothing at all. Only a full row is safe to hand back.
            if base:
                for key, value in base.items():
                    if key not in merged and value not in ("", [], None):
                        merged[key] = value
            out[row_id] = merged

        if missing:
            sys.exit("upstream menu has no rows: " + ", ".join(sorted(missing)))

        # Upstream's own menu with those rows replaced, rather than the rows on
        # their own. This file IS the defaults file the shell reads -- nixarchy
        # points OMARCHY_PATH at a tree carrying it -- so it has to be complete.
        # Written by updating a copy of upstream's, which keeps upstream's row
        # order: the menu renders in the order the object is written.
        full = dict(upstream)
        full.update(out)

        header = (
            "// Generated by nixarchy: Omarchy's own menu with the rows that\n"
            "// would run pacman replaced by the Nix app selection.\n"
            "//\n"
            "// This is the DEFAULTS file -- OMARCHY_PATH points at a tree whose\n"
            "// default/omarchy/omarchy-menu.jsonc is this one. Your own file,\n"
            "// ~/.config/omarchy/extensions/omarchy-menu.jsonc, is untouched by\n"
            "// nixarchy and overrides anything here by id, which is exactly what\n"
            "// upstream designed it for. Add rows there, or declare them with\n"
            "// programs.nixarchy.menu.extraEntries to have them generated here.\n"
        )
        open(out_path, "w").write(header + json.dumps(full, indent=2, ensure_ascii=False) + "\n")
        print(f"menu defaults: {len(full)} rows, {len(out)} of them nixarchy's")
        PY
      '';

  # The tree OMARCHY_PATH points at: the package's own share/omarchy, with
  # exactly one file replaced.
  #
  # Built here rather than in pkgs/omarchy because the rewrites depend on the
  # machine's app selection, which is per-configuration, not per-package. The
  # idiom is flake.nix's nixarchy-plymouth: mirror a subtree out of the omarchy
  # package rather than rebuild the package for one file.
  #
  # Symlinks at the shallowest level that works, and real files in the one
  # directory being changed. That matters for more than size: upstream's own
  # scripts copy out of $OMARCHY_PATH at runtime (omarchy refresh, the
  # migrations, omarchy-plugin-clone), and a symlink FARM would hand them
  # links into a read-only store path where they expect files. Symlinking whole
  # directories instead keeps everything inside them a real file, which is what
  # `cp -r $OMARCHY_PATH/config/.` copies.
  omarchyTree = pkgs.runCommand "nixarchy-omarchy-tree" { } ''
    src=${cfg.package}/share/omarchy
    mkdir -p $out/default/omarchy

    # Everything except the one directory on the way to the file, including
    # dotfiles -- .luarc.json and .editorconfig are part of the tree the
    # AGENTS.md in it tells an agent to read.
    shopt -s dotglob
    for entry in "$src"/*; do
      [ "$(basename "$entry")" = default ] || ln -s "$entry" $out/
    done
    for entry in "$src"/default/*; do
      [ "$(basename "$entry")" = omarchy ] || ln -s "$entry" $out/default/
    done

    cp --no-preserve=mode "$src"/default/omarchy/* $out/default/omarchy/
    cp --no-preserve=mode ${menuDefaults} $out/default/omarchy/omarchy-menu.jsonc
  '';

in
{
  options.programs.nixarchy = {
    # Declared as individual options rather than one submodule holding them
    # all: evaluating an outer submodule's _module.freeformType forces config,
    # and config here defines programs.* for the module-backed apps, which is
    # a cycle. One option per app has no such wrapper to evaluate.
    apps = lib.mapAttrs (
      name: app:
      lib.mkOption {
        type = lib.types.submodule { options = appModule name app; };
        default = { };
        description = "${app.label} (${app.category}).";
      }
    ) available;

    menu.extraEntries = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = { };
      example = lib.literalExpression ''
        { "personal.notes" = { icon = "󰎞"; label = "Notes"; action = "omarchy-launch-editor ~/notes"; }; }
      '';
      description = ''
        Extra rows merged into Omarchy's menu, keyed by dotted id. Reuse an
        existing id to override it.

        Upstream reads a single extension file, so nixarchy manages it and this
        option is how to add your own rows -- editing the file directly would
        be overwritten on the next rebuild.
      '';
    };

    flake = lib.mkOption {
      type = lib.types.str;
      default = "/etc/nixos";
      example = "/home/alice/nixos-config";
      description = ''
        Flake directory that `nixarchy-apply` copies the app selection into
        before rebuilding.

        A flake cannot read a file outside its own source tree, so the
        generated ~/.config/nixarchy/apps.nix has to be copied in rather than
        imported from $HOME. Import the copy from your flake:

            imports = [ ./nixarchy-apps.nix ];
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      appModuleConfig
      {
        # What OMARCHY_PATH resolves to on this machine. modules/home.nix reads
        # it across from here for the same reason it reads localAi.resolved:
        # the value is computed from the app selection, which only this module
        # can see, and a home-manager configuration with no NixOS module falls
        # back to the package's own tree.
        programs.nixarchy.tree = omarchyTree;

        # nixarchy defaults allowUnfree on, so reaching this warning means it
        # was deliberately turned back off. Keep it: that user is exactly the
        # one who needs the predicate escape hatch named.
        warnings = lib.optional (needsUnfree && !(config.nixpkgs.config.allowUnfree or false)) ''
          nixarchy: an enabled app is unfree but nixpkgs.config.allowUnfree is
          off, so the build will fail with a licence error. nixarchy defaults it
          on; something in your configuration sets it false. Allow it, or add just
          this app to nixpkgs.config.allowUnfreePredicate.
        '';

        # Exported so the Home Manager module can seed it, and so a user can
        # always diff their file against the current full list.
        environment.etc = {
          "nixarchy/apps-template.nix".source = appsTemplate;
          "nixarchy/services-template.nix".source = servicesTemplate;
          "nixarchy/advanced-template.nix".source = advancedTemplate;
          # The generated defaults, exported so CI and `nixarchy-doctor` can
          # read what this machine's menu actually says without resolving
          # OMARCHY_PATH. The tree below is what the shell reads.
          "nixarchy/omarchy-menu.jsonc".source = menuDefaults;
        };

        environment.systemPackages = [
          # The doctor and verify, which until now were flake apps only.
          #
          # `nixarchy doctor` has always been an advertised subcommand, and on
          # every machine where you can type `nixarchy` it answered "The doctor
          # is not installed". The dispatcher below already has
          # `if command -v nixarchy-doctor` and routes to it -- a branch nothing
          # could take, because nothing installed it.
          #
          # Running from the flake is unchanged: that entry point exists so the
          # doctor can be run BEFORE nixarchy is an input anywhere, and
          # installing it does not take that away.
          #
          # Through the overlay on the user's own pkgs, never
          # inputs.self.packages -- see the note on programs.nixarchy.package in
          # modules/nixos.nix for what mixing nixpkgs instances does to buildEnv.
          (pkgs.extend inputs.self.overlays.default).nixarchy-doctor
          (pkgs.extend inputs.self.overlays.default).nixarchy-verify

          # Uncomments one app in ~/.config/nixarchy/apps.nix. Matching is on
          # the `#@ <id>` marker, not a line number or a label, so the file
          # survives being reformatted, reordered or annotated by hand.
          # What the catalogue offers that your file has never heard of.
          #
          # The seeded files are written once and never touched again, which is
          # correct -- they are the user's, and overwriting one would silently
          # undo a selection. The consequence is that an entry added after a
          # machine was installed never appears on it: no `#@` marker, so
          # nixarchy-app-enable answers "no app 'x' in $file" and the menu row
          # is dead. Until now the only way to find that out was to diff
          # against /etc/nixarchy/apps-template.nix by hand, and nothing said
          # so.
          (pkgs.writeShellApplication {
            name = "nixarchy-catalogue-diff";
            runtimeInputs = [
              pkgs.gnugrep
              pkgs.gnused
              pkgs.coreutils
            ];
            text = ''
              add=false
              case "''${1:-}" in
                --add) add=true ;;
                "") ;;
                *)
                  echo "usage: nixarchy-catalogue-diff [--add]" >&2
                  exit 2
                  ;;
              esac

              dir="''${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy"
              total=0

              for part in apps services advanced; do
                user="$dir/$part.nix"
                tpl="/etc/nixarchy/$part-template.nix"
                [ -f "$user" ] && [ -f "$tpl" ] || continue

                # Compared by marker, never by line: the file's own header
                # invites reformatting, reordering and annotating, so anything
                # positional would report a file somebody had tidied as full of
                # holes. A marker with a space after #@ is a catalogue row; the
                # others -- #@pkg, #@opt, #@pkgs-begin -- are the user's own and
                # a template never has them.
                missing=$(
                  comm -23 \
                    <(grep -oE "#@ [a-z0-9_.-]+" "$tpl" | sort -u) \
                    <(grep -oE "#@ [a-z0-9_.-]+" "$user" | sort -u)
                )
                [ -n "$missing" ] || continue

                count=$(printf '%s\n' "$missing" | grep -c . || true)
                total=$((total + count))
                echo "$part.nix is missing $count:"

                rows=""
                while IFS= read -r marker; do
                  [ -n "$marker" ] || continue
                  echo "  ''${marker#\#@ }"
                  row=$(grep -F -- "$marker" "$tpl" | head -1)
                  # App rows are written relative to programs.nixarchy.apps,
                  # which they sit inside in the template. Appended at the end
                  # of a file they would be outside it -- harmless while
                  # commented and broken the moment somebody uncommented one.
                  # Written in full they are correct wherever they land. A
                  # second `programs.nixarchy.apps = { }` block would not be:
                  # two definitions of one attribute in one set is an error,
                  # not a merge.
                  if [ "$part" = apps ]; then
                    row=$(printf '%s' "$row" |
                      sed -E "s/^([[:space:]]*#[[:space:]]*)/\1programs.nixarchy.apps./")
                  fi
                  rows="$rows$row
              "
                done <<MARKERS
              $missing
              MARKERS

                if [ "$add" = true ]; then
                  # Before the module's closing brace, not after it. Appending
                  # to the end of the file puts the rows outside the attrset,
                  # where they parse -- they are comments -- and stop parsing
                  # the moment somebody uncomments one, because that is content
                  # after the final `}`. Which is the same trap the full-path
                  # rewrite above exists to avoid, one line further down.
                  close=$(grep -n "^}" "$user" | tail -1 | cut -d: -f1)
                  if [ -z "$close" ]; then
                    echo "  $user has no closing brace on its own line;" >&2
                    echo "  add these by hand rather than let this guess:" >&2
                    printf '%s' "$rows" >&2
                    continue
                  fi
                  tmp=$(mktemp)
                  head -n "$((close - 1))" "$user" >"$tmp"
                  {
                    echo ""
                    echo "  # ── Added by nixarchy-catalogue-diff, $(date +%Y-%m-%d) ──"
                    printf '%s' "$rows"
                  } >>"$tmp"
                  tail -n "+$close" "$user" >>"$tmp"
                  cat "$tmp" >"$user"
                  rm -f "$tmp"
                  echo "  appended to $user"
                fi
              done

              if [ "$total" -eq 0 ]; then
                echo "your files have everything the catalogue offers"
                exit 0
              fi

              if [ "$add" = false ]; then
                echo ""
                echo "Run 'nixarchy-catalogue-diff --add' to append these as"
                echo "commented-out lines. Nothing you have written changes:"
                echo "only new lines, at the end, under a dated heading."
              fi
            '';
          })

          (pkgs.writeShellApplication {
            name = "nixarchy-service-enable";
            runtimeInputs = [
              pkgs.gnused
              pkgs.gnugrep
              pkgs.coreutils
              cfg.package
            ];
            text = ''
              file="''${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy/services.nix"
              id="''${1:?usage: nixarchy-service-enable <service-id>}"

              # Validated before it reaches sed and grep, which the app scripts
              # do not do: the id is interpolated into a regex, and an id with a
              # slash or a bracket in it would either fail obscurely or match
              # something nobody meant. Ids come from data/services.nix and look
              # like this; anything else is a typo or a caller with a bug.
              case "$id" in
                *[!a-z0-9_-]* | "")
                  echo "nixarchy: '$id' is not a service id" >&2
                  exit 2
                  ;;
              esac

              [ -f "$file" ] || { echo "no $file -- log in again to have it created" >&2; exit 1; }

              if ! grep -qE "#@ $id([[:space:]]|\$)" "$file"; then
                echo "nixarchy: no service '$id' in $file" >&2
                echo "  The full list is /etc/nixarchy/services-template.nix." >&2
                exit 1
              fi

              # Already on if the marked line is not commented out.
              #
              # Deliberately not the app scripts' test, which greps for
              # `^[[:space:]]*<id>.enable` -- that cannot work here, because a
              # plain entry's line begins with services.openssh, not with the
              # id. Asking whether the marked line is live is also the more
              # honest question: it does not answer "yes" to `enable = false;`.
              if grep -qE "^[[:space:]]*[^#[:space:]].*#@ $id([[:space:]]|\$)" "$file"; then
                echo "$id is already enabled; run nixarchy-apply to build it"
                exit 0
              fi

              sed -i -E "/#@ $id([[:space:]]|\$)/ s/^([[:space:]]*)# ?/\1/" "$file"

              queued=$(grep -cE "^[[:space:]]*[^#[:space:]].*#@ " "$file" || true)
              if command -v omarchy-notification-send >/dev/null 2>&1; then
                omarchy-notification-send -r 8471 -t 8000 -u normal \
                  "$id queued -- not enabled yet" \
                  "$queued selected. Click here, or Install > Apply changes, to run nixos-rebuild." \
                  --exec omarchy-launch-floating-terminal-with-presentation nixarchy-apply || true
              fi
              echo "enabled $id in $file ($queued queued)"
              echo "run 'nixarchy-apply' when you have picked everything you want"
            '';
          })

          (pkgs.writeShellApplication {
            name = "nixarchy-service-disable";
            runtimeInputs = [
              pkgs.gnused
              pkgs.gnugrep
              pkgs.coreutils
            ];
            text = ''
              file="''${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy/services.nix"
              id="''${1:?usage: nixarchy-service-disable <service-id>}"

              case "$id" in
                *[!a-z0-9_-]* | "")
                  echo "nixarchy: '$id' is not a service id" >&2
                  exit 2
                  ;;
              esac

              [ -f "$file" ] || { echo "no $file" >&2; exit 1; }

              if ! grep -qE "#@ $id([[:space:]]|\$)" "$file"; then
                echo "nixarchy: no service '$id' in $file" >&2
                exit 1
              fi

              # Comment the marked line back out. Turning a service off is not
              # the same as uninstalling it: the daemon stops, and whatever it
              # wrote -- a Syncthing database, an authorised key -- stays where
              # it is. Removing that is the user's call and not this script's.
              sed -i -E "/#@ $id([[:space:]]|\$)/ s/^([[:space:]]*)([^[:space:]#])/\1# \2/" "$file"
              echo "disabled $id in $file"
              echo "run 'nixarchy-apply' to rebuild without it"
            '';
          })

          (pkgs.writeShellApplication {
            name = "nixarchy-app-enable";
            runtimeInputs = [
              pkgs.gnused
              pkgs.gnugrep
              pkgs.coreutils
              cfg.package # omarchy-notification-send
            ];
            text = ''
              file="''${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy/apps.nix"
              id="''${1:?usage: nixarchy-app-enable <app-id>}"

              [ -f "$file" ] || { echo "no $file -- log in again to have it created" >&2; exit 1; }

              if ! grep -qE "#@ $id([[:space:]]|\$)" "$file"; then
                echo "nixarchy: no app '$id' in $file" >&2
                exit 1
              fi

              if grep -q "^[[:space:]]*$id\.enable" "$file"; then
                echo "$id is already enabled; run nixarchy-apply to build it"
                exit 0
              fi

              # Strip one leading '# ' from the marked line, nothing else.
              sed -i -E "/#@ $id([[:space:]]|\$)/ s/^([[:space:]]*)# ?/\1/" "$file"

              # A menu pick runs with no terminal attached, so stdout goes
              # nowhere and the pick looks like it did nothing at all. Say so
              # on the desktop instead. -r keeps repeated picks replacing one
              # notification rather than stacking a wall of them.
              queued=$(grep -cE "^[[:space:]]*[a-z0-9_-]+\.enable" "$file" || true)
              if command -v omarchy-notification-send >/dev/null 2>&1; then
                # --exec makes the notification clickable: nothing is built
                # until a rebuild runs, so the notification that says so is
                # also the way to start it.
                omarchy-notification-send -r 8471 -t 8000 -u normal \
                  "$id queued -- not installed yet" \
                  "$queued app(s) selected. Click here, or Install > Apply changes, to run nixos-rebuild." \
                  --exec omarchy-launch-floating-terminal-with-presentation nixarchy-apply || true
              fi
              echo "enabled $id in $file ($queued queued)"
              echo "run 'nixarchy-apply' when you have picked everything you want"
            '';
          })

          # The inverse of nixarchy-app-enable: re-comments the line. It only
          # ever touches ~/.config/nixarchy/apps.nix -- never the user's own
          # NixOS configuration, which nixarchy does not own and must not
          # edit. An app stays installed until a rebuild runs.
          (pkgs.writeShellApplication {
            name = "nixarchy-app-disable";
            runtimeInputs = [
              pkgs.gnused
              pkgs.gnugrep
              pkgs.coreutils
              cfg.package
            ];
            text = ''
              file="''${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy/apps.nix"
              id="''${1:?usage: nixarchy-app-disable <app-id>}"

              [ -f "$file" ] || { echo "no $file" >&2; exit 1; }

              if ! grep -qE "#@ $id([[:space:]]|\$)" "$file"; then
                echo "nixarchy: no app '$id' in $file" >&2
                exit 1
              fi

              if ! grep -qE "^[[:space:]]*$id\.enable" "$file"; then
                echo "$id is not enabled"
                exit 0
              fi

              # Comment the line back out, preserving its indentation.
              sed -i -E "/#@ $id([[:space:]]|\$)/ s/^([[:space:]]*)([^[:space:]#])/\1# \2/" "$file"

              queued=$(grep -cE "^[[:space:]]*[a-z0-9_-]+\.enable" "$file" || true)
              if command -v omarchy-notification-send >/dev/null 2>&1; then
                omarchy-notification-send -r 8471 -t 8000 -u normal \
                  "$id removed from your selection" \
                  "$queued app(s) still selected. Click here to run nixos-rebuild and apply it." \
                  --exec omarchy-launch-floating-terminal-with-presentation nixarchy-apply || true
              fi
              echo "disabled $id in $file ($queued still enabled)"
              echo "it stays installed until 'nixarchy-apply' rebuilds"
            '';
          })

          # An interactive picker over what is currently selected, for the
          # Remove > Package row. Upstream offers a fuzzy picker over installed
          # pacman packages; this is the same shape over the app selection.
          (pkgs.writeShellApplication {
            name = "nixarchy-app-remove";
            runtimeInputs = [
              pkgs.gnugrep
              pkgs.gnused
              pkgs.coreutils
              pkgs.fzf
            ];
            text = ''
              file="''${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy/apps.nix"
              [ -f "$file" ] || { echo "no $file" >&2; exit 1; }

              mapfile -t enabled < <(
                grep -oE "^[[:space:]]*[a-z0-9_-]+\.enable" "$file" \
                  | sed -E 's/[[:space:]]*//; s/\.enable//'
              )
              if [ ''${#enabled[@]} -eq 0 ]; then
                echo "Nothing is selected. Install > Package lists what is available."
                exit 0
              fi

              chosen=$(printf '%s\n' "''${enabled[@]}" | fzf --multi \
                --prompt="remove > " \
                --header="tab to select several, enter to confirm") || exit 0
              [ -n "$chosen" ] || exit 0

              while IFS= read -r app; do
                [ -n "$app" ] && nixarchy-app-disable "$app"
              done <<< "$chosen"

              echo
              echo "Run 'nixarchy-apply' to rebuild without them."
            '';
          })

          # The answer to "I want a package the menu does not offer". Upstream's
          # `omarchy pkg add` runs pacman; there is no imperative equivalent
          # here, so this does the declarative thing instead -- appends the
          # attribute to a list in the same file the menu already edits, so
          # one `nixarchy-apply` builds curated apps and extras together.
          #
          # It deliberately does NOT touch the user's own NixOS configuration,
          # which nixarchy does not own. ~/.config/nixarchy/apps.nix is already
          # a full NixOS module, so a systemPackages list can sit beside the
          # app selection with no new file and no new option.
          (pkgs.writeShellApplication {
            name = "nixarchy-pkg-add";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.gnused
              pkgs.gawk
              pkgs.jq
              config.nix.package
              cfg.package # omarchy-notification-send
            ];
            text = ''
              file="''${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy/apps.nix"
              table=${appAttrTable}
              nixpkgs=${pkgs.path}

              if [ $# -eq 0 ]; then
                echo "usage: nixarchy-pkg-add <nixpkgs-attribute>..." >&2
                echo "  e.g. nixarchy-pkg-add ripgrep fd" >&2
                exit 1
              fi

              [ -f "$file" ] || { echo "no $file -- log in again to have it created" >&2; exit 1; }

              # Every edit below is reverted as a unit if the result will not parse. The
              # file is the user's own NixOS module; leaving it broken would take the whole
              # system's evaluation down with it, not just this feature.
              backup=$(mktemp)
              cp "$file" "$backup"
              trap 'rm -f "$backup"' EXIT
              restore() { cp "$backup" "$file"; }

              # The list this appends to does not exist in a freshly generated file: the
              # template is all curated apps and nothing else. Create it once, in place,
              # before the module's closing brace.
              ensure_block() {
                grep -q '#@pkgs-end' "$file" && return 0

                # systemPackages needs `pkgs`, and the generated template takes `{ ... }:`.
                if ! sed -n '/^{/{p;q}' "$file" | grep -q 'pkgs'; then
                  sed -i -E '0,/^\{[[:space:]]*\.\.\.[[:space:]]*\}:[[:space:]]*$/s//{ pkgs, ... }:/' "$file"
                fi

                tmp=$(mktemp)
                awk '
                  !ins && /^}[[:space:]]*$/ {
                    print "";
                    print "  # ── Extra packages ──────────────────────────────────────────────";
                    print "  # Plain nixpkgs attributes, added by nixarchy-pkg-add. These are";
                    print "  # not part of the curated app list above: the Omarchy menu does";
                    print "  # not offer them and will not remove them. The file stays yours --";
                    print "  # reformat and annotate freely, the tool only ever inserts one";
                    print "  # line before the end marker.";
                    print "  environment.systemPackages = with pkgs; [  #@pkgs-begin";
                    print "  ];  #@pkgs-end";
                    ins = 1;
                  }
                  { print }
                ' "$file" > "$tmp"
                mv "$tmp" "$file"

                if ! grep -q '#@pkgs-end' "$file"; then
                  echo "nixarchy: could not find the closing '}' of $file." >&2
                  echo "Add this to it by hand, then run this again:" >&2
                  echo >&2
                  echo "  environment.systemPackages = with pkgs; [  #@pkgs-begin" >&2
                  echo "  ];  #@pkgs-end" >&2
                  restore
                  exit 1
                fi

                if ! sed -n '/^{/{p;q}' "$file" | grep -q 'pkgs'; then
                  echo "nixarchy: $file does not take a 'pkgs' argument, so the list just" >&2
                  echo "added cannot refer to it. Change its first line to:  { pkgs, ... }:" >&2
                fi
              }

              added=()

              for attr in "$@"; do
                case "$attr" in
                  "" | -* | .* | *..* | *[!A-Za-z0-9_.-]*)
                    echo "'$attr' is not a nixpkgs attribute name." >&2
                    exit 1
                    ;;
                esac

                # The curated list first. Typing `firefox` should get you the app, which is
                # a NixOS module and brings policies and extensions with it, not a bare
                # package in systemPackages that does none of that.
                app=$(awk -F'\t' -v a="$attr" '$1 == a { print $2; exit }' "$table")
                if [ -n "$app" ]; then
                  echo "$attr is on the curated app list, as '$app'. Enable it that way --"
                  echo "that route knows whether it needs a NixOS module rather than a package:"
                  echo
                  echo "  nixarchy-app-enable $app"
                  echo
                  continue
                fi

                if grep -q "#@pkg $attr\$" "$file"; then
                  echo "$attr is already in $file"
                  continue
                fi

                # Resolved against the system's own nixpkgs rather than the flake registry,
                # so the answer matches what a rebuild would actually build, and it works
                # with no network. nix-instantiate rather than `nix eval`: no pure-eval mode
                # to fight over an absolute store path, and no experimental flag to require.
                # allowUnfree only so an unfree package reports as unfree instead of
                # throwing here; nothing in this script decides your licence policy.
                if ! info=$(nix-instantiate --eval --strict --json --expr "
                  let
                    p = import $nixpkgs { config.allowUnfree = true; };
                    q = p.$attr;
                    ls = if q.meta ? license then
                           (if builtins.isList q.meta.license then q.meta.license else [ q.meta.license ])
                         else [ ];
                  in {
                    inherit (q) name;
                    description = q.meta.description or \"\";
                    unfree = !(builtins.all (l: if builtins.isAttrs l then (l.free or true) else true) ls);
                    broken = q.meta.broken or false;
                  }" 2>/dev/null); then
                  echo "nixpkgs has no package '$attr'." >&2
                  echo >&2
                  echo "Search for the right name:" >&2
                  echo "  nix search nixpkgs $attr" >&2
                  echo "  https://search.nixos.org/packages" >&2
                  exit 1
                fi

                ensure_block
                sed -i "/#@pkgs-end/i\\    $attr  #@pkg $attr" "$file"

                # sed reports success when its address matches nothing, which would leave
                # this reporting a package it never wrote. Check the line is really there.
                if ! grep -q "#@pkg $attr\$" "$file"; then
                  restore
                  echo "nixarchy: failed to write $attr into $file. Nothing was changed." >&2
                  exit 1
                fi
                added+=("$attr")

                echo "added $attr ($(jq -r .name <<<"$info")) -- $(jq -r '.description // ""' <<<"$info")"
                if [ "$(jq -r .unfree <<<"$info")" = true ]; then
                  echo "  unfree: needs nixpkgs.config.allowUnfree in your configuration, or the build fails."
                fi
                if [ "$(jq -r .broken <<<"$info")" = true ]; then
                  echo "  marked broken in nixpkgs: expect the build to fail."
                fi
              done

              [ ''${#added[@]} -gt 0 ] || exit 0

              if ! nix-instantiate --parse "$file" >/dev/null 2>&1; then
                restore
                echo "nixarchy: that would have left $file unparseable. Nothing was changed." >&2
                exit 1
              fi

              count=$(grep -c '#@pkg ' "$file" || true)

              # A menu pick runs with no terminal attached, so stdout goes nowhere. Say it
              # on the desktop instead, clickable, because a rebuild is what is still owed.
              if command -v omarchy-notification-send >/dev/null 2>&1; then
                omarchy-notification-send -r 8471 -t 8000 -u normal \
                  "''${added[*]} queued -- not installed yet" \
                  "$count extra package(s) selected. Click here, or Install > Apply changes, to run nixos-rebuild." \
                  --exec omarchy-launch-floating-terminal-with-presentation nixarchy-apply || true
              fi

              echo
              echo "run 'nixarchy-apply' when you have picked everything you want"
            '';
          })

          # Search everything this machine could install, and route the choice
          # to whichever writer is right for it.
          #
          # The three kinds are not interchangeable and the whole point of one
          # picker over them is that you do not have to know which is which:
          # an app becomes programs.<name>, a package becomes a systemPackages
          # entry, an option becomes a line of its own. Picking Firefox from
          # the app rows and picking `firefox` from the package rows are
          # genuinely different configurations, and the rows say so.
          #
          # The index is built from this system's own nixpkgs and its own
          # options, not from search.nixos.org. It is slower to build and it
          # cannot go stale against the machine, which is the trade that
          # matters: an index that offers a package nixarchy-pkg-add will then
          # refuse is worse than no index.
          (pkgs.writeShellApplication {
            name = "nixarchy-search";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.gnused
              pkgs.gawk
              pkgs.jq
              pkgs.fzf
              pkgs.curl
              config.nix.package
            ];
            text = ''
              file="''${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy/apps.nix"
              cache="''${XDG_CACHE_HOME:-$HOME/.cache}/nixarchy"
              index="$cache/index.tsv"
              stamp="$cache/stamp"

              appindex=${appIndexTable}
              flatpakrows=${flatpakIndexRows}
              optionsjson=${optionsJsonPath}
              nixpkgs=${pkgs.path}

              reindex=0
              [ "''${1:-}" = "--reindex" ] && { reindex=1; shift; }

              # One index, four tab-separated fields: kind, name, one-line summary, option
              # type, and the preview text with its newlines escaped. The preview is carried
              # in the line rather than looked up on selection because fzf runs the preview
              # command on every keystroke, and a jq pass over 19 MB of package metadata is
              # not something to do sixty times a second.
              build_index() {
                mkdir -p "$cache"
                tmp=$(mktemp)

                # Curated apps first, so they sort above the raw nixpkgs attribute of the
                # same name. Enabling `firefox` as an app gets you programs.firefox; adding
                # it as a package does not.
                awk -F'\t' -v OFS='\t' '{
                  note = ($4 == "" ? "" : "\\n\\n" $4)
                  print "app", $1, $2 " (" $3 ")", "",
                    "OMARCHY APP  " $1 "\\n\\n" $2 "\\n" $3 \
                    note "\\n\\nEnabling this writes a line in your app selection:\\n  " \
                    $1 ".enable = true;"
                }' "$appindex" > "$tmp"

                # Empty when this system builds no manual, in which case the
                # picker is packages and apps only rather than not working at all.
                if [ -n "$optionsjson" ] && [ -f "$optionsjson" ]; then
                  jq -r '
                    def val(x):
                      if x == null then "(none)"
                      elif (x | type) == "object" then (x.text // (x | tostring))
                      else (x | tostring) end;
                    to_entries[] | .key as $k | .value as $v |
                    [ "opt", $k,
                      (($v.description // "") | gsub("[\n\t ]+"; " ") | .[0:110]),
                      ($v.type // ""),
                      ( "NIXOS OPTION  " + $k
                        + "\n\ntype:     " + ($v.type // "?")
                        + "\ndefault:  " + val($v.default)
                        + (if $v.example == null then "" else "\nexample:  " + val($v.example) end)
                        + "\n\n" + ($v.description // "(undocumented)")
                        + "\n\ndeclared in:\n  " + (($v.declarations // []) | join("\n  "))
                      )
                    ] | @tsv' "$optionsjson" >> "$tmp"
                else
                  echo "  no option index: documentation.nixos.enable is off on this" >&2
                  echo "  system, so there is no options.json to read." >&2
                fi

                # The system's own nixpkgs, not the flake registry: an index that offers a
                # package this machine cannot build is worse than no index. Slow enough to
                # be worth saying so -- about a minute, once per system generation.
                echo "  indexing nixpkgs (this takes about a minute)..." >&2
                nix search --json --extra-experimental-features 'nix-command flakes' \
                  "path:$nixpkgs" ^ 2>/dev/null |
                  jq -r '
                    to_entries[] | (.key | sub("^legacyPackages\\.[^.]+\\."; "")) as $a | .value as $v |
                    [ "pkg", $a,
                      (($v.description // "") | gsub("[\n\t ]+"; " ") | .[0:110]),
                      "",
                      ( "NIXPKGS PACKAGE  " + $a
                        + "\n\nversion:  " + ($v.version // "?")
                        + "\n\n" + ($v.description // "(no description)")
                        + "\n\nAdding this writes it into your app selection:\n  "
                        + "environment.systemPackages = with pkgs; [ " + $a + " ];"
                      )
                    ] | @tsv' >> "$tmp"

                # Curated flatpaks and the Flathub entry point. A plain cat:
                # these rows are already in the index's five-field shape, and
                # they are local, so building the index still needs no network.
                cat "$flatpakrows" >> "$tmp"

                mv "$tmp" "$index"
                readlink -f /run/current-system > "$stamp"
              }

              if [ "$reindex" = 1 ] || [ ! -s "$index" ] ||
                 [ "$(cat "$stamp" 2>/dev/null)" != "$(readlink -f /run/current-system)" ]; then
                echo "Building the search index. This happens once per system generation." >&2
                build_index
              fi

              selection=$(fzf --multi \
                --delimiter='\t' --with-nth=1,2,3 --nth=2,3 \
                --preview 'printf "%b\n" {5}' \
                --preview-window='right,58%,wrap' \
                --prompt='nixarchy > ' \
                --header='enter to select · tab for several · esc to cancel' \
                --query="''${*:-}" < "$index") || exit 0
              [ -n "$selection" ] || exit 0

              [ -f "$file" ] || { echo "no $file -- log in again to have it created" >&2; exit 1; }

              backup=$(mktemp)
              cp "$file" "$backup"
              trap 'rm -f "$backup"' EXIT

              changed=0
              scaffolded=0
              written=0

              # Options are written at the module's top level, before its closing brace.
              # Nothing here parses Nix: the brace is found textually and the result is
              # checked with nix-instantiate before anything is kept.
              insert_line() {
                tmp=$(mktemp)
                awk -v payload="$1" '
                  !ins && /^}[[:space:]]*$/ { printf "%s", payload; ins = 1 }
                  { print }
                ' "$file" > "$tmp"
                mv "$tmp" "$file"
              }

              add_option() {
                path=$1
                type=$2

                if grep -q "#@opt $path\$" "$file"; then
                  echo "$path is already in $file"
                  return 0
                fi

                value=""
                case "$type" in
                  boolean)
                    value=$(printf 'true\nfalse\n' | fzf --height=6 --prompt="$path = ") || return 0
                    ;;
                  "one of "*)
                    value=$(printf '%s' "''${type#one of }" | grep -oE '"[^"]*"' |
                      fzf --height=12 --prompt="$path = ") || return 0
                    ;;
                esac

                if [ -n "$value" ]; then
                  insert_line "\n  $path = $value;  #@opt $path\n"
                  echo "set $path = $value"
                  changed=1
                  written=$((written + 1))
                  return 0
                fi

                # Anything else. An option's value is arbitrary Nix -- a submodule, a
                # function, a package, a list of them -- and a picker that pretended
                # otherwise would write plausible-looking wrong configuration. So it writes
                # what it does know, commented out, in the right file, and leaves the
                # expression to you.
                {
                  printf '\n'
                  grep -P "^opt\t\Q$path\E\t" "$index" | head -1 |
                    cut -f5 | sed 's/\\n/\n/g' | sed 's/^/  # /'
                  printf '  # %s = ;  #@opt %s\n' "$path" "$path"
                } > "$cache/scaffold.$$"
                insert_line "$(cat "$cache/scaffold.$$")
              "
                rm -f "$cache/scaffold.$$"
                echo "scaffolded $path (commented out -- set the value and uncomment it)"
                changed=1
                written=$((written + 1))
                scaffolded=$((scaffolded + 1))
              }

              # Ask flathub.org directly.
              #
              # NOT `flatpak search`, which is columnar with no JSON output and
              # needs both a configured remote and a downloaded appstream cache
              # -- so it answers nothing on a machine that has not set flatpak
              # up yet, which is exactly the machine asking.
              #
              # This is the one thing in the picker that needs a network. The
              # index itself is still built entirely from local sources, so the
              # other three kinds keep working on a machine with none; only
              # this row fails, and it says so.
              flathub_search() {
                local query hits picked id line
                read -r -p "Search Flathub for: " query || return 0
                [ -n "$query" ] || return 0

                # --fail so an HTTP error is an error rather than an error page
                # parsed as zero results, which is the failure that looks like
                # "nothing matched" and sends someone hunting for a typo.
                if ! hits=$(curl -sS --fail -m 20 \
                      -X POST https://flathub.org/api/v2/search \
                      -H 'Content-Type: application/json' \
                      -d "$(jq -nc --arg q "$query" '{query: $q, filters: []}')" 2>&1); then
                  echo "nixarchy: could not reach flathub.org." >&2
                  echo "  Searching Flathub needs a network; the other rows in this picker do not." >&2
                  return 1
                fi

                picked=$(printf '%s' "$hits" |
                  jq -r '.hits[]? | [.app_id, (.name // ""), ((.summary // "") | gsub("[\n\t]"; " "))] | @tsv' |
                  fzf --multi --with-nth=2.. --delimiter='\t' \
                      --prompt="flathub > " --height=80% \
                      --preview='echo {1}' --preview-window=down,3) || return 0
                [ -n "$picked" ] || { echo "nothing on Flathub matched '$query'"; return 0; }

                while IFS=$'\t' read -r id _ _; do
                  [ -n "$id" ] || continue
                  # In the catalogue? Then it has been checked, and the normal
                  # writer handles it.
                  if grep -qE "^flatpak\t[^\t]+\t" "$index" &&
                     awk -F'\t' -v i="$id" '$1=="flatpak" && $2==i {found=1} END {exit !found}' "$index"; then
                    nixarchy-service-enable "$id" && changed=1
                    continue
                  fi
                  # Otherwise print it rather than write it. Nixarchy has not
                  # checked this app, and generating configuration for an id
                  # nobody has looked at is not a thing to do on someone's
                  # behalf.
                  line="  services.flatpak.packages = [ \"$id\" ];"
                  echo
                  echo "$id is not in nixarchy's catalogue, so nothing was written."
                  echo "Add this to ~/.config/nixarchy/advanced.nix yourself:"
                  echo
                  echo "$line"
                done <<< "$picked"
                echo
                echo "then run 'nixarchy-apply'"
              }

              while IFS=$'\t' read -r kind name _ type _; do
                [ -n "$kind" ] || continue
                case "$kind" in
                  app) nixarchy-app-enable "$name" && changed=1 ;;
                  pkg) nixarchy-pkg-add "$name" && changed=1 ;;
                  opt) add_option "$name" "$type" ;;
                  # nixarchy-service-enable, not a flatpak-specific command:
                  # the rows live in services.nix and carry the same #@ markers,
                  # so the writer that already exists is the right one.
                  flatpak)
                    if [ "$name" = "flathub" ]; then
                      flathub_search
                    else
                      nixarchy-service-enable "$name" && changed=1
                    fi
                    ;;
                esac
              done <<< "$selection"

              [ "$changed" = 1 ] || exit 0

              if ! nix-instantiate --parse "$file" >/dev/null 2>&1; then
                cp "$backup" "$file"
                echo "nixarchy: that would have left $file unparseable. Nothing was changed." >&2
                exit 1
              fi

              if [ "$scaffolded" -gt 0 ]; then
                echo
                echo "$scaffolded option(s) are commented out in $file. Edit them first:"
                echo "  omarchy-launch-editor $file"
              fi

              # Only when this script wrote something itself: nixarchy-app-enable and
              # nixarchy-pkg-add each print this line already, and saying it twice reads
              # like two separate things happened.
              if [ "$written" -gt 0 ]; then
                echo
                echo "run 'nixarchy-apply' when you have picked everything you want"
              fi
            '';
          })

          # `nixarchy dev init <preset>`. Its own file because flake.nix's
          # devenv-presets check runs THIS command rather than a copy of it --
          # see pkgs/dev-init.nix.
          #
          # Installed unconditionally, unlike devenv itself, which is an opt-in
          # catalogue entry. The command's first act is to check for devenv and
          # name the entry that installs it, and that answer is only useful on a
          # machine that has not enabled it yet.
          (pkgs.callPackage ../pkgs/dev-init.nix { })

          # `nixarchy vm <subcommand>`. Its own file for the same reason as
          # dev-init.nix above: `checks.microvm-template` (#224) has to run
          # the real command. See pkgs/microvm.nix for what it does and why.
          (pkgs.callPackage ../pkgs/microvm.nix { inherit (inputs) self; })

          # One name for the commands this repo adds, and a way through to
          # the 431 it vendors.
          #
          # Not a rename of Omarchy. Upstream's commands keep upstream's name,
          # because they are upstream's -- `omarchy theme set` is the same
          # script here as on Arch, and a bug in it is a bug to report there.
          # What this names is the other half: the commands nixarchy wrote,
          # which until now were binaries on PATH with nothing tying them
          # together and no way to discover them.
          #
          # Anything this does not own falls through to omarchy unchanged, so
          # `nixarchy theme set catppuccin` works and does exactly what
          # `omarchy theme set catppuccin` does. The fallthrough is the point:
          # you should not have to know which half of the desktop you are
          # talking to before you can type a command.
          (pkgs.writeShellApplication {
            name = "nixarchy";
            runtimeInputs = [
              pkgs.coreutils
              cfg.package # omarchy, for the fallthrough
            ];
            text = ''
              # Routed by hand rather than by scanning a bin/ directory the way
              # upstream's dispatcher does: these commands are separate
              # derivations on PATH, not siblings in one tree, so there is no
              # directory to scan. A handful of entries is not a table worth
              # generating.
              case "''${1:-}" in
                search)   shift; exec nixarchy-search "$@" ;;
                apply)    shift; exec nixarchy-apply "$@" ;;
                # Not installed on the system, on purpose: the doctor exists
                # to be run *before* nixarchy is an input anywhere, which is
                # the only entry point someone deciding whether to adopt it
                # actually has. Route to the command that works rather than to
                # a binary that is not there.
                verify)   shift; exec nixarchy-verify "$@" ;;
                doctor)
                  if command -v nixarchy-doctor >/dev/null 2>&1; then
                    shift; exec nixarchy-doctor "$@"
                  fi
                  echo "The doctor is not installed -- it runs from the flake, so that it" >&2
                  echo "works on a machine that has not adopted nixarchy yet:" >&2
                  echo >&2
                  echo "  nix run github:olafkfreund/nixarchy#doctor" >&2
                  exit 1
                  ;;
                pkg)
                  case "''${2:-}" in
                    add) shift 2; exec nixarchy-pkg-add "$@" ;;
                  esac
                  ;;
                app)
                  case "''${2:-}" in
                    enable)  shift 2; exec nixarchy-app-enable "$@" ;;
                    disable) shift 2; exec nixarchy-app-disable "$@" ;;
                    remove)  shift 2; exec nixarchy-app-remove "$@" ;;
                  esac
                  ;;
                dev)
                  case "''${2:-}" in
                    init) shift 2; exec nixarchy-dev-init "$@" ;;
                  esac
                  ;;
                vm) shift; exec nixarchy-vm "$@" ;;
                ""|--help|-h|help)
                  cat <<'USAGE'
              nixarchy -- the Omarchy desktop, vendored for NixOS.

              Commands this port adds:

                nixarchy search [query]     Every package, NixOS option and app, in one picker
                nixarchy pkg add <attr>     Add a nixpkgs package to the app selection
                nixarchy app enable <id>    Select an app from the curated list
                nixarchy app disable <id>   Deselect one
                nixarchy app remove         Pick what to deselect, interactively
                nixarchy apply              Copy the selection into your flake and rebuild
                nixarchy dev init <preset>  Scaffold a devenv project here (no argument lists them)
                nixarchy vm <subcommand>    Disposable NixOS MicroVMs -- 'nixarchy vm help'
                nixarchy doctor             What this machine needs to run nixarchy

              Everything else is Omarchy's own, and reaches it unchanged:

                nixarchy theme set <name>   = omarchy theme set <name>
                nixarchy update             = omarchy update
                omarchy commands            Every one of them

              Both names work for those. They are the same scripts as on Arch,
              which is why they keep Omarchy's name: a bug in one is a bug to
              report upstream, not here.
              USAGE
                  exit 0
                  ;;
              esac

              # Anything else is Omarchy's. Not a warning and not a wrapper:
              # exec, so the exit status, the terminal and the signals are the
              # command's own.
              exec omarchy "$@"
            '';
          })

          # Copies the selection into the flake and switches. Kept separate
          # from enabling so several apps can be picked before anything builds.
          (pkgs.writeShellApplication {
            name = "nixarchy-apply";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.diffutils
              pkgs.gnugrep
              # nh rather than nixos-rebuild: a progress view that says what is
              # building and how far along it is, and a package diff against the
              # running generation once it lands. Both matter more here than
              # anywhere else -- this is the command a menu pick runs, in front
              # of someone who just clicked "install" and has no other signal
              # that anything is happening. It is also the smaller closure of
              # the two, by about 200 MiB.
              pkgs.nh
            ];
            text = ''
              file="''${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy/apps.nix"
              flake="''${NIXARCHY_FLAKE:-${cfg.flake}}"

              # Where the selection lands: this machine's directory when the
              # flake has one, the flake root when it does not.
              #
              # That second case is every machine installed before the hosts/
              # layout existed. Their flake is their own -- the README calls it
              # "a flake you own" -- so nothing migrates it, and this one
              # conditional is the entire cost of leaving them alone.
              #
              # Keyed on the directory existing rather than on the hostname
              # matching anything: a repo that has hosts/ but not one for THIS
              # machine is a repo being edited from somewhere else, and writing
              # a stray directory into it would be worse than writing the file
              # where it has always gone.
              base="$flake"
              # uname -n, not hostname(1): writeShellApplication builds a
              # strict PATH from runtimeInputs, and hostname lives in a package
              # this script does not depend on. uname is coreutils, already
              # here, and reports the same name.
              host=$(uname -n)
              if [ -d "$flake/hosts/$host" ]; then
                base="$flake/hosts/$host"
              fi
              dest="$base/nixarchy-apps.nix"

              [ -f "$file" ] || { echo "no $file" >&2; exit 1; }
              [ -d "$flake" ] || {
                echo "nixarchy: flake directory '$flake' does not exist." >&2
                echo "Set programs.nixarchy.flake, or export NIXARCHY_FLAKE." >&2
                exit 1
              }

              echo "Enabled apps:"
              grep -E "^[[:space:]]*[a-z0-9_-]+\.enable" "$file" || echo "  (none)"
              echo

              # A flake cannot read a file outside its own tree, so the
              # selection is copied in rather than imported from $HOME.
              #
              # Three files now, into $flake/nixarchy/, with nixarchy-apps.nix
              # left as a module that imports them. That last part is the whole
              # reason for the indirection: the README has been telling people
              # to add `imports = [ ./nixarchy-apps.nix ];` since the beginning,
              # and on a machine nixarchy does not own, asking them to add two
              # more lines is not a thing this project gets to do. The name they
              # already wrote keeps working and gains two files behind it.
              #
              # Safe to overwrite because nixarchy-apps.nix has always been a
              # copy this script regenerates, never something the user wrote --
              # and the copy it used to hold is written to nixarchy/apps.nix in
              # the same run, before the stub replaces it.
              srcdir="''${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy"
              mkdir -p "$base/nixarchy"

              imports=""
              copied=""
              for part in apps services advanced; do
                src="$srcdir/$part.nix"
                [ -f "$src" ] || continue
                dst="$base/nixarchy/$part.nix"
                imports="$imports ./nixarchy/$part.nix"
                if [ -f "$dst" ] && diff -q "$src" "$dst" >/dev/null; then
                  continue
                fi
                cp "$src" "$dst"
                copied="$copied $part"
              done

              # Only what exists is imported. A machine seeded before
              # services.nix existed has two files, not three, and a stub
              # importing a path that is not there fails to evaluate.
              {
                echo "# Generated by nixarchy-apply. Do not edit -- your files"
                echo "# are ~/.config/nixarchy/{apps,services,advanced}.nix and"
                echo "# this is regenerated from them on every apply."
                echo "{"
                echo "  imports = [$imports ];"
                echo "}"
              } >"$dest"

              if [ -n "$copied" ]; then
                echo "copied ->$copied"
              else
                echo "$base is already up to date."
              fi

              # Stage what was written, or a flake in a git worktree cannot see
              # it. This is not a nicety: git makes untracked files invisible to
              # the evaluator, so a fresh nixarchy/services.nix fails with "path
              # does not exist" -- the trap installer/mkFlake.nix documents and
              # the installer works around by staging at install time.
              #
              # Guarded: /etc/nixos is root-owned, and a failure to stage should
              # print the fix rather than abort an apply that has already
              # copied everything correctly.
              if [ -e "$flake/.git" ]; then
                git -C "$flake" add -A nixarchy nixarchy-apps.nix 2>/dev/null || {
                  echo
                  echo "NOTE: could not stage the copies in $flake."
                  echo "  A flake in a git repository sees only tracked files,"
                  echo "  so the rebuild may fail with \"path does not exist\"."
                  echo "  Fix with: sudo git -C $flake add -A"
                  echo
                }
              fi

              # Whether anything in the flake actually imports it.
              #
              # Copying the selection in is only half the job: a flake cannot
              # read a file outside its own tree, so the copy is necessary, and
              # importing it is the user's. Nothing checked that, so a machine
              # that never added the import got the full ceremony -- the menu
              # marking apps enabled, this script reporting a copy, a rebuild
              # running to completion -- and installed nothing, every time. It
              # took someone asking why `dictation.enable = true` never
              # installed anything to notice.
              #
              # Excludes the copy itself, which of course contains its own name
              # nowhere but is matched by the filename glob.
              importers=$(grep -rl 'nixarchy-apps\.nix' "$flake" \
                --include='*.nix' 2>/dev/null |
                grep -v '/nixarchy-apps\.nix$' || true)

              if [ -z "$importers" ]; then
                echo
                echo "WARNING: nothing in $flake imports nixarchy-apps.nix."
                echo
                echo "  The selection has been copied, and a rebuild will"
                echo "  ignore it: every app you enable will look installed"
                echo "  and never be built."
                echo
                echo "  Add it to this host's configuration:"
                echo "    imports = [ ./nixarchy-apps.nix ];"
                echo
                echo "  The path is relative to the file you put it in, so a"
                echo "  host under hosts/<name>/ needs ../../nixarchy-apps.nix"
                echo "  or however many levels up the flake root is."
                echo
              fi

              read -r -p "Build and switch now? [y/N] " reply
              case "$reply" in
                # No sudo: nh elevates itself, and wrapping it means the
                # elevation happens before nh can decide how to do it.
                #
                # The flake is passed explicitly rather than left to nh's own
                # default. nh reads $NH_FLAKE, which plenty of people already
                # export at whatever configuration they usually work on -- and
                # an app selection copied into one flake then switched into
                # another is a failure that looks like nothing happening.
                [yY]*) exec nh os switch "$flake" ;;
                *) echo "Not switching. Run: nh os switch $flake" ;;
              esac
            '';
          })
        ]
        ++ appPackages;
      }
    ]
  );
}
