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

  # Same gate modules/services/boxes.nix itself applies -- the menu rows
  # below must not exist at all (not just be hidden) when boxes are off, the
  # same "Nix-level: lib.optionalAttrs cfg.enable" #226 already established
  # for sandboxes.
  boxesEnabled = cfg.enable && cfg.services.boxes.enable;
  boxTemplates = import ../data/box-templates.nix;

  # Why: modules/AGENTS.md#the-command-each-app-puts-on-path-so-the-menu-can-
  appBinary =
    name: app:
    let
      path = lib.splitString "." (app.attr or name);
      probe = builtins.tryEval (
        let
          p = if app.ours or false then cfg.apps.${name}.package or null else lib.attrByPath path null pkgs;
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

  # Why: modules/AGENTS.md#the-curated-list-as-search-rows
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
        # The fifth field marks the rows `nixarchy try` can run: only an app
        # backed by a package attribute is runnable. A module app (firefox,
        # docker) has nothing to execute, so its preview must not sell a key
        # that would only print a refusal.
        "${name}\t${app.label}\t${app.category}\t${flat (app.note or "")}\t${
          if app ? attr then "try" else ""
        }\n"
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

  # Why: modules/AGENTS.md#flatpaks-go-in-services-nix-rather-than-a-fourth-f
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

  # The tier below the Flathub row: software in no repository at all (#581).
  # Same five-field shape, whole row on one line, preview newlines escaped --
  # the same rules the flathub row above documents. One static row, so
  # `nixarchy pkg new` is findable from the picker at all. Findable is the
  # honest word: the picker is a single fzf call, so this row appears only
  # when the query happens to match its own text -- a search for the missing
  # package's NAME matches nothing and closes the picker. The reliable
  # signpost is nixarchy-pkg-add's miss message, which names the command;
  # docs/manual/other-packages.md states the limitation.
  pkgNewIndexRow = pkgs.writeText "nixarchy-pkg-new-row.tsv" (
    "new	pkg-new	Missing from nixpkgs? Draft a new package from a source URL		"
    + "NOT IN NIXPKGS\\n\\nWhen nixpkgs, the app list and Flathub all miss, this drafts a derivation from the software's own source URL (e.g. a GitHub repo) with nix-init, builds it once, and keeps the draft either way.\\n\\nPicking this asks for the URL, then runs:\\n  nixarchy pkg new <url>\\n\\nNeeds a network. The result is a draft for you to review, not a finished package.\n"
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
    # Why: modules/AGENTS.md#services-and-system-settings-as-nixos-configuratio
    { ... }:
    {
    ${lib.concatStrings (map serviceCategoryBlock serviceCategories)}${flatpakBlock}}
  '';

  # No catalogue, on purpose.
  advancedTemplate = pkgs.writeText "nixarchy-advanced.nix" ''
    # Why: modules/AGENTS.md#anything-at-all
    { ... }:
    {
    }
  '';

  appsTemplate = pkgs.writeText "nixarchy-apps.nix" ''
    # Why: modules/AGENTS.md#applications-available-through-the-omarchy-menu-as
    { ... }:
    {
      programs.nixarchy.apps = {
    ${lib.concatStrings (map templateCategory categories)}  };
    }

    # Offered by the Omarchy menu but with no nixpkgs equivalent:
    ${unavailableNote}'';
  # Why: modules/AGENTS.md#the-menu-defaults
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

        # Why: modules/AGENTS.md#backup-and-recovery-one-menu-542
        "system.recovery" = {
          icon = "󰁯";
          label = "Backup and recovery";
          aliases = [
            "recovery"
            "restore"
            "backup"
          ];
        };

        # Restores before backups, in source order: #542 wants an emergency
        # read left-to-right as "what to try first", and Menu.qml lists a
        # parent's children in the order this file declares their ids in.
        "system.recovery.rollback" = {
          icon = "󰕍";
          label = "Roll back";
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-rollback";
          description = "Switch to an earlier system generation. Your home directory is not touched";
        };

        # Explicit `parent`: MenuModel.js's default parent for this id is
        # "system.recovery.snapshot" (its own id with the last segment
        # dropped) -- the PEER row below, not this menu. Left to the
        # default, this row would render one level too deep: invisible when
        # browsing System > Backup and recovery, reachable only by search --
        # the same trap trigger.snapshot.restore was already in under
        # Trigger, and the reason system.recovery.home-backup.restore below
        # needs the same override.
        "system.recovery.snapshot.restore" = {
          icon = "󰦛";
          label = "Restore from snapshot";
          parent = "system.recovery";
          action = "omarchy-launch-floating-terminal-with-presentation omarchy-snapshot restore";
          description = "Open an earlier version of your home directory and copy back what you want";
        };

        # Why: modules/AGENTS.md#the-off-disk-half-beside-the-on-disk-one
        "system.recovery.home-backup.restore" = {
          icon = "󰇚";
          label = "Restore desktop config";
          parent = "system.recovery";
          when = "nixarchy-home-backup --check";
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-home-backup restore";
          description = "Copy your bar, keybindings and themes back out of the backup. Works on a new machine";
        };

        # Upstream's snapshots are taken by its updater and restored from
        # the boot menu, and neither happens here. This is a new row, so it
        # carries its own label and icon.
        "system.recovery.snapshot" = {
          icon = "󰆓";
          label = "Snapshot home";
          action = "omarchy-launch-floating-terminal-with-presentation omarchy-snapshot create";
          description = "Save your home directory as it is now. Instant, and costs nothing until files change";
        };

        "system.recovery.home-backup" = {
          icon = "󰁯";
          label = "Back up desktop config";
          when = "nixarchy-home-backup --check";
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-home-backup";
          description = "Push your bar, keybindings and themes to a private git repository. Survives the disk";
        };

        # Why: modules/AGENTS.md#beside-roll-back-because-they-are-the-two-halves-o
        "system.recovery.backup" = {
          icon = "󰆔";
          label = "Back up configuration";
          when = "test -e /etc/nixarchy/managed";
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-config-repo";
          description = "Commit and push this machine's NixOS configuration, so a reinstall can bring it back";
        };

        # Deliberately not called "backup" -- #478 names the trap: someone
        # loses a disk, boots the "backup", and gets a clean machine with
        # none of their files. The image reinstalls the SYSTEM; files come
        # back from the rows above.
        "system.recovery.reinstall-iso" = {
          icon = "󰗮";
          label = "Build reinstall image";
          when = "nixarchy-reinstall-iso --check";
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-reinstall-iso";
          description = "A bootable image that reinstalls this machine's system on new hardware. Not a backup: it carries none of your files";
        };

        "install.aur" = {
          when = "false";
        };

        # Upstream wears the Arch logo here and runs `pacman -Rns` on the
        # selection. This picks over the app selection instead, and only ever
        # edits ~/.config/nixarchy/apps.nix -- never the user's own NixOS
        # configuration, which nixarchy does not own. One picker for all
        # three kinds the Install picker writes -- apps, extra packages,
        # options -- so Remove covers what Install can add (#494, #522).
        "remove.package" = {
          icon = "󰭌";
          label = "App / package";
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-app-remove";
          description = "Deselect apps, added packages and options, then Apply changes to rebuild without them";
        };

        # Upstream's label is "Omarchy" and its action pulls a git checkout and
        # runs pacman. The action is already replaced (see pkgs/omarchy/nix-bin);
        # this is the label catching up with what it now does.
        "update.omarchy" = {
          icon = "󰭌";
          label = "Nixarchy";
          description = "nh os switch --update: move every flake input forward, then rebuild";
        };

        # Omarchy's release channels are a pacman repository choice, and two
        # of its four have a meaning here (#529).
        #
        # This block used to hide all five rows, with a reason that has since
        # stopped being true in both halves: "there is nothing to switch", and
        # "switching nixpkgs would mean editing the user's own system flake,
        # which nixarchy does not own". There is something to switch --
        # nixos-26.05 or unstable -- and `nixarchy-channel` does that edit
        # consensually, under the rule nixarchy-unfreeze set: only lines this
        # project wrote get rewritten, a flake somebody has reshaped is theirs
        # and gets the edit printed instead of guessed at, and nixpkgs and
        # home-manager move together because neither project supports the
        # mismatch.
        #
        # `rc` and `dev` stay hidden. They are pacman repositories with no
        # NixOS equivalent, and inventing a meaning for them would be worse
        # than leaving them out -- a row that does something other than what
        # its name says is the failure this menu has the most guards against.
        #
        # The children are still hidden individually: hiding a parent keeps
        # its rows out of the menu tree, but they stay reachable through
        # search and `omarchy menu summon`.
        "update.channel" = {
          icon = "󰓾";
          label = "Channel";
          description = "Follow stable or unstable nixpkgs. Nixarchy is developed against unstable";
        };
        "update.channel.stable" = {
          icon = "󰋼";
          label = "Stable";
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-channel stable";
          description = "nixos-26.05 and the matching home-manager. Less tested here, not more";
        };
        "update.channel.edge" = {
          icon = "󰇾";
          label = "Unstable";
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-channel unstable";
          description = "nixos-unstable, what nixarchy is developed and tested against";
        };
        "update.channel.rc" = {
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
        # Beside Apply, because it answers the question Apply raises: what
        # does this change look like, before the machine switches to it?
        # NOT "nixarchy vm" -- that name is taken by MicroVM sandboxes, and
        # docs/manual/sandboxes.md says outright "Not nixarchy's own test
        # VM". #485 settles the name.
        "install.preview" = {
          icon = "󰍹";
          label = "Preview changes";
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-preview";
          description = "Build this configuration and boot it in a VM window, before switching the machine to it";
        };
        "install.apply" = {
          icon = "";
          label = "Apply changes";
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-apply";
          description = "Copy the selection into your flake and nixos-rebuild switch";
        };
      }
      // lib.optionalAttrs boxesEnabled (
        {
          # A new parent under Trigger, appended after upstream's own rows --
          # the same precedent system.recovery above already set for this
          # file (#542), and the one #226 set for sandboxes.
          # `when` is the runtime half of the gate: whether podman is
          # actually usable THIS login is only knowable now, not at rebuild
          # time -- the Nix-level half is `boxesEnabled` just above, which
          # keeps the row from existing at all when the feature is off.
          "trigger.box" = {
            icon = "󰆧";
            label = "Boxes";
            aliases = [
              "box"
              "distrobox"
            ];
            when = "nixarchy box --check";
          };

          "trigger.box.enter" = {
            icon = "󰆍";
            label = "Enter a box";
            action = "omarchy-launch-floating-terminal-with-presentation nixarchy box enter";
            description = "Pick a box you already have and get a shell in it";
          };

          "trigger.box.rm" = {
            icon = "󰩹";
            label = "Remove a box";
            action = "omarchy-launch-floating-terminal-with-presentation nixarchy box rm";
            description = "Pick a box and delete it";
          };
        }
        // lib.mapAttrs' (
          name: template:
          lib.nameValuePair "trigger.box.create.${name}" {
            icon = "󰐕";
            label = "New: ${template.label}";
            action = "omarchy-launch-floating-terminal-with-presentation nixarchy box create --template ${name}";
            description = template.note;
          }
        ) boxTemplates
      )
      // lib.optionalAttrs cfg.enable {
        # Why: modules/AGENTS.md#the-sandboxes-group-226
        "trigger.vm" = {
          icon = "󰦛";
          label = "Sandbox";
          aliases = [
            "vm"
            "sandbox"
            "microvm"
          ];
          when = "nixarchy-vm --check";
        };
        "trigger.vm.new" = {
          icon = "󰕍";
          label = "New sandbox";
          # `create`, not `new`. The menu KEY is trigger.vm.new and the action
          # was written to match the key instead of the CLI, so every click
          # printed "nixarchy-vm: unknown subcommand 'new'" and closed. The
          # sibling rows only work because run/stop/rm happen to be spelled the
          # same on both sides; checks.menu-verbs now asserts that rather than
          # leaving it to coincidence.
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-vm create";
          description = "Name one, pick a template, and open it";
        };
        "trigger.vm.open" = {
          icon = "󰁯";
          label = "Open a sandbox";
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-vm run";
          description = "Attach to one you already created";
        };
        "trigger.vm.stop" = {
          icon = "󰉉";
          label = "Stop a sandbox";
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-vm stop";
          description = "Ask a running sandbox to shut down";
        };
        "trigger.vm.destroy" = {
          icon = "󱄅";
          label = "Destroy a sandbox";
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-vm rm";
          description = "Delete it and its state -- cannot be undone";
        };
        "trigger.vm.list" = {
          icon = "󰆓";
          label = "List sandboxes";
          action = "omarchy-launch-floating-terminal-with-presentation nixarchy-vm list";
          description = "What you have created, and which are running";
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
                # Why: modules/AGENTS.md#dim-when-the-app-is-in-the-selection-or-already-on
                disabled =
                  "grep -qE '^[[:space:]]*${name}\\.enable' $HOME/.config/nixarchy/apps.nix"
                  + " || command -v ${appBinary name app} >/dev/null 2>&1";
                description = "Enable in ~/.config/nixarchy/apps.nix, then Apply changes";
              }
          )
        ) (lib.filterAttrs (_: a: a ? menuId) apps)
      )
      # Why: modules/AGENTS.md#the-services-catalogue-as-menu-rows
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

  # Why: modules/AGENTS.md#the-tree-omarchy-path-points-at
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

    # ---- the per-package escape (#530) --------------------------------
    #
    # The machine follows one channel; this is how a single package comes
    # from the other one.
    #
    # ## Why a module argument and not an overlay
    #
    # An overlay rewrites every reverse-dependency, so pulling one package
    # from another channel would rebuild everything that depends on it. This
    # hands the other package set to modules as `pkgsOther` and touches
    # nothing else: the blast radius is exactly the attributes someone names.
    #
    # It is also the shape that keeps the user's choice on top. Nothing here
    # moves `pkgs`. A machine on stable stays on stable, and the only packages
    # that come from anywhere else are the ones written down.
    #
    # ## The cost, which the docs must state and the tools must print
    #
    # Two channels share NOTHING in the store, even at identical versions.
    # Measured 2026-09-10: btop, same version, 0 shared paths, 51 MB
    # duplicated; vlc 3.0.23-2, same version, 0 shared paths, 1.5 GB. So this
    # is a deliberate per-package decision and never a default.
    #
    # ## What it cannot do
    #
    # Packages only. A NixOS *module* comes from the package set the system is
    # evaluated with, and `disabledModules` plus a foreign import is a footgun
    # this does not hand anyone -- so an `option` row cannot cross channels
    # and the tooling says so rather than half-working.
    otherChannel = {
      flake = lib.mkOption {
        type = lib.types.nullOr lib.types.raw;
        default = null;
        example = lib.literalExpression "inputs.nixpkgs-unstable";
        description = ''
          A second nixpkgs flake input, made available to this configuration
          as the module argument `pkgsOther`.

          Null by default, which is the answer for almost every machine.
          Nothing on it is used unless a configuration names `pkgsOther`.

          Set it to the OTHER channel from the one this machine follows: a
          stable machine points it at unstable, and the reverse. Adding it
          costs nothing until something references `pkgsOther`; each package
          that does costs its whole closure, because the two channels share no
          store paths even at identical versions.
        '';
      };

      config = lib.mkOption {
        type = lib.types.attrs;
        default = { inherit (pkgs.config) allowUnfree allowUnfreePredicate; };
        defaultText = lib.literalExpression "{ inherit (pkgs.config) allowUnfree allowUnfreePredicate; }";
        description = ''
          nixpkgs config for the other channel. Defaults to carrying this
          machine's unfree answer across, because a package that is allowed
          here and refused there would fail with nixpkgs' unfree message and
          nothing pointing at the cause.

          Overlays are deliberately NOT carried over: nixarchy's overlay
          builds Omarchy against the package set it is applied to, and doing
          that twice is a second full desktop nobody asked for.
        '';
      };
    };

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

  config = lib.mkMerge [
    {
      # OUTSIDE the mkIf below, and that is not a style choice (#530).
      #
      # `_module.args` is what the module system uses to build the arguments
      # every module is called with. Defining one under `mkIf cfg.enable`
      # means evaluating the condition needs `config`, which needs the
      # modules, which need their arguments -- infinite recursion, reported
      # somewhere unhelpful.
      #
      # A `throw` rather than `null` when no other channel is configured:
      # `pkgsOther` is only ever forced by a configuration that named it, and
      # the person who wrote `pkgsOther.helix` deserves a sentence telling
      # them what to add, not `attribute 'helix' missing`.
      _module.args.pkgsOther =
        if cfg.otherChannel.flake == null then
          throw ''
            nixarchy: something in this configuration refers to `pkgsOther`,
            and no other channel is configured. Add a second nixpkgs to your
            flake and point the option at it:

                inputs.nixpkgs-other.url = "github:NixOS/nixpkgs/nixos-unstable";

                programs.nixarchy.otherChannel.flake = inputs.nixpkgs-other;

            The two channels share no store paths even at identical versions,
            so each package taken from the other one costs its whole closure.
          ''
        else
          import cfg.otherChannel.flake {
            inherit (pkgs.stdenv.hostPlatform) system;
            config = cfg.otherChannel.config;
          };
    }

    (lib.mkIf cfg.enable (
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
            # Why: modules/AGENTS.md#the-doctor-and-verify-which-until-now-were-flake-a
            (pkgs.extend inputs.self.overlays.default).nixarchy-doctor
            (pkgs.extend inputs.self.overlays.default).nixarchy-verify

          ]
          # The default agent's own package, when the configuration names one.
          #
          # ids and attributes are omarchy-default-agent's `attr_for`, kept in
          # step by hand. That command installs an agent through nixarchy-pkg-add
          # when someone picks one from the menu; this is the same decision made
          # in the configuration instead, so it reproduces on the next machine.
          #
          # `claude-code` is unfree, so defaultAgent = "claude" without
          # programs.nixarchy.allowUnfree fails to evaluate with nixpkgs' own
          # message naming the package. That is the right failure: the
          # alternative is a missing agent and an Ask menu that never appears.
          ++
            lib.optional (cfg.defaultAgent != null)
              {
                # Three of the seven are named after their own command, which is
                # the whole reason omarchy-agent can look for `$agent` on PATH.
                inherit (pkgs) codex opencode crush;

                claude = pkgs.claude-code;
                gemini = pkgs.gemini-cli;
                copilot = pkgs.github-copilot-cli;
                grok = pkgs.grok-cli;
              }
              .${cfg.defaultAgent}
          ++ [

            # Why: modules/AGENTS.md#uncomments-one-app-in-config-nixarchy-apps-nix
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
            #
            # All four kinds the pickers can write, because "Remove" that
            # only sees some of them is a menu row that lies (#494, #522): curated
            # apps (`id.enable` lines), extra packages (`#@pkg` markers from
            # nixarchy-pkg-add), options (`#@opt` markers from the Search
            # picker's add_option) and drafts (`#@draft` markers from
            # nixarchy-pkg-new).
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

                # `|| continue`, not `&&`: this script runs under set -e, and a
                # failing AND-list on a blank line would end it mid-collect.
                entries=()
                while IFS= read -r name; do
                  [ -n "$name" ] || continue
                  entries+=("app"$'\t'"$name")
                done < <(
                  grep -oE "^[[:space:]]*[a-z0-9_-]+\.enable" "$file" \
                    | sed -E 's/[[:space:]]*//; s/\.enable//'
                )
                while IFS= read -r name; do
                  [ -n "$name" ] || continue
                  entries+=("pkg"$'\t'"$name")
                done < <(grep -oE '#@pkg [A-Za-z0-9_.-]+$' "$file" | sed 's/^#@pkg //')
                while IFS= read -r name; do
                  [ -n "$name" ] || continue
                  entries+=("opt"$'\t'"$name")
                done < <(grep -o '#@opt .*' "$file" | sed 's/^#@opt //' | sort -u)
                while IFS= read -r name; do
                  [ -n "$name" ] || continue
                  entries+=("draft"$'\t'"$name")
                done < <(grep -oE '#@draft [A-Za-z0-9_.-]+$' "$file" | sed 's/^#@draft //')

                if [ ''${#entries[@]} -eq 0 ]; then
                  echo "Nothing is selected. Install > Package lists what is available."
                  exit 0
                fi

                # The preview shows the line that would go, so what "remove"
                # means for each entry is visible before it happens.
                chosen=$(printf '%s\n' "''${entries[@]}" | fzf --multi \
                  --delimiter='\t' \
                  --prompt="remove > " \
                  --header="tab to select several, enter to confirm" \
                  --preview "grep -F -- {2} '$file' | grep -F -e '.enable' -e '#@'" \
                  --preview-window='down,3,wrap') || exit 0
                [ -n "$chosen" ] || exit 0

                # Packages and options are batched: one backup, one parse check,
                # one notification per kind rather than per line.
                pkgsel=()
                optsel=()
                draftsel=()
                while IFS=$'\t' read -r kind name; do
                  [ -n "$name" ] || continue
                  case "$kind" in
                    app) nixarchy-app-disable "$name" ;;
                    pkg) pkgsel+=("$name") ;;
                    opt) optsel+=("$name") ;;
                    draft) draftsel+=("$name") ;;
                  esac
                done <<< "$chosen"
                [ ''${#pkgsel[@]} -eq 0 ] || nixarchy-pkg-remove "''${pkgsel[@]}"
                [ ''${#optsel[@]} -eq 0 ] || nixarchy-opt-remove "''${optsel[@]}"
                [ ''${#draftsel[@]} -eq 0 ] || nixarchy-pkg-undraft "''${draftsel[@]}"

                echo
                echo "Run 'nixarchy-apply' to rebuild without them."
              '';
            })

            # The inverse of nixarchy-pkg-add. It deletes only lines carrying the
            # `#@pkg` marker -- the marker is the writer's claim of ownership --
            # and never reformats anything else: the file is the user's. The
            # systemPackages block stays even when its last marked line goes,
            # because the user may have put their own, unmarked lines in it, and
            # an empty list evaluates fine.
            (pkgs.writeShellApplication {
              name = "nixarchy-pkg-remove";
              runtimeInputs = [
                pkgs.coreutils
                pkgs.gnugrep
                pkgs.gnused
                pkgs.fzf
                config.nix.package
                cfg.package # omarchy-notification-send
              ];
              text = ''
                file="''${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy/apps.nix"
                [ -f "$file" ] || { echo "no $file" >&2; exit 1; }

                if [ $# -eq 0 ]; then
                  mapfile -t attrs < <(grep -oE '#@pkg [A-Za-z0-9_.-]+$' "$file" | sed 's/^#@pkg //')
                  if [ ''${#attrs[@]} -eq 0 ]; then
                    echo "No extra packages are selected. 'nixarchy pkg add' or the Search picker adds one."
                    exit 0
                  fi
                  chosen=$(printf '%s\n' "''${attrs[@]}" | fzf --multi \
                    --prompt="remove pkg > " \
                    --header="tab to select several, enter to confirm") || exit 0
                  [ -n "$chosen" ] || exit 0
                  mapfile -t picked <<< "$chosen"
                  set -- "''${picked[@]}"
                fi

                # Reverted as a unit if anything goes wrong, exactly as the
                # writer's edits are: the file is the user's own NixOS module.
                backup=$(mktemp)
                cp "$file" "$backup"
                trap 'rm -f "$backup"' EXIT
                restore() { cp "$backup" "$file"; }

                removed=()
                for attr in "$@"; do
                  # Same alphabet nixarchy-pkg-add accepts. Anything else would
                  # reach the sed address below as a pattern, not a name.
                  case "$attr" in
                    "" | -* | .* | *..* | *[!A-Za-z0-9_.-]*)
                      restore
                      echo "'$attr' is not a nixpkgs attribute name." >&2
                      exit 1
                      ;;
                  esac
                  if ! grep -qF -- "#@pkg $attr" "$file"; then
                    restore
                    echo "nixarchy: no package '$attr' in $file. Nothing was changed." >&2
                    exit 1
                  fi
                  # Exactly the marked line nixarchy-pkg-add wrote, wherever the
                  # user has moved it to.
                  sed -i "/#@pkg $attr\$/d" "$file"
                  removed+=("$attr")
                done

                [ ''${#removed[@]} -gt 0 ] || exit 0

                if ! nix-instantiate --parse "$file" >/dev/null 2>&1; then
                  restore
                  echo "nixarchy: that would have left $file unparseable. Nothing was changed." >&2
                  exit 1
                fi

                count=$(grep -c '#@pkg ' "$file" || true)
                if command -v omarchy-notification-send >/dev/null 2>&1; then
                  omarchy-notification-send -r 8471 -t 8000 -u normal \
                    "''${removed[*]} removed from your selection" \
                    "$count extra package(s) still selected. Click here to run nixos-rebuild and apply it." \
                    --exec omarchy-launch-floating-terminal-with-presentation nixarchy-apply || true
                fi
                for attr in "''${removed[@]}"; do
                  echo "removed $attr from $file"
                done
                echo "it stays installed until 'nixarchy-apply' rebuilds"
              '';
            })

            # The inverse of the apps.nix line `nixarchy pkg new` wrote, and
            # deliberately NOT of its draft file: deleting
            # ~/.config/nixarchy/packages/<name>.nix, or the copy
            # nixarchy-apply put in the flake, is an edit to a tree the user
            # owns, not this tool's call -- so this drops the marked line and
            # prints where the draft file still is. The `#@draft` marker
            # survives the user uncommenting the line (the same property
            # `#@opt` has), so the commented and the live form are both
            # removable, by the same sed.
            (pkgs.writeShellApplication {
              name = "nixarchy-pkg-undraft";
              runtimeInputs = [
                pkgs.coreutils
                pkgs.gnugrep
                pkgs.gnused
                pkgs.fzf
                config.nix.package
                cfg.package # omarchy-notification-send
              ];
              text = ''
                file="''${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy/apps.nix"
                [ -f "$file" ] || { echo "no $file" >&2; exit 1; }

                list_drafts() {
                  grep -oE '#@draft [A-Za-z0-9_.-]+$' "$file" | sed 's/^#@draft //'
                }

                if [ $# -eq 0 ]; then
                  mapfile -t names < <(list_drafts)
                  if [ ''${#names[@]} -eq 0 ]; then
                    echo "No drafts are in $file. 'nixarchy pkg new <url>' drafts one."
                    exit 0
                  fi
                  chosen=$(printf '%s\n' "''${names[@]}" | fzf --multi \
                    --prompt="remove draft > " \
                    --header="tab to select several, enter to confirm" \
                    --preview "grep -F -- '#@draft '{} '$file'" \
                    --preview-window='down,3,wrap') || exit 0
                  [ -n "$chosen" ] || exit 0
                  mapfile -t picked <<< "$chosen"
                  set -- "''${picked[@]}"
                fi

                # Reverted as a unit if anything goes wrong, exactly as
                # nixarchy-pkg-remove's edits are: the file is the user's own
                # NixOS module.
                backup=$(mktemp)
                cp "$file" "$backup"
                trap 'rm -f "$backup"' EXIT
                restore() { cp "$backup" "$file"; }

                removed=()
                for name in "$@"; do
                  # Same alphabet nixarchy-pkg-new accepts. Anything else would
                  # reach the sed address below as a pattern, not a name.
                  case "$name" in
                    "" | -* | .* | *..* | *[!A-Za-z0-9_.-]*)
                      restore
                      echo "'$name' is not a draft name." >&2
                      exit 1
                      ;;
                  esac
                  # Exact string, not a substring: `#@draft foo` must not
                  # answer for `#@draft foobar`.
                  if ! list_drafts | grep -qFx -- "$name"; then
                    restore
                    echo "nixarchy: no draft '$name' in $file. Nothing was changed." >&2
                    echo "'nixarchy pkg remove' takes out a #@pkg line instead." >&2
                    exit 1
                  fi
                  # The marked line wherever the user moved it, commented or
                  # uncommented. Dots escaped: the name lands in a sed address.
                  sed -i "/#@draft ''${name//./\\.}\$/d" "$file"
                  removed+=("$name")
                done

                [ ''${#removed[@]} -gt 0 ] || exit 0

                if ! nix-instantiate --parse "$file" >/dev/null 2>&1; then
                  restore
                  echo "nixarchy: that would have left $file unparseable. Nothing was changed." >&2
                  exit 1
                fi

                if command -v omarchy-notification-send >/dev/null 2>&1; then
                  omarchy-notification-send -r 8471 -t 8000 -u normal \
                    "''${removed[*]} removed from your selection" \
                    "The draft file itself is kept. Click here to run nixos-rebuild and apply it." \
                    --exec omarchy-launch-floating-terminal-with-presentation nixarchy-apply || true
                fi
                pkgdir="''${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy/packages"
                for name in "''${removed[@]}"; do
                  echo "removed $name from $file"
                  [ ! -e "$pkgdir/$name.nix" ] || \
                    echo "the draft file is yours and stays at $pkgdir/$name.nix"
                done
                echo "a draft that was live stays installed until 'nixarchy-apply' rebuilds"
              '';
            })

            # Removes an option the Search picker wrote (#522). What "remove"
            # means here follows nixarchy-channel's rule -- only lines this
            # project wrote get rewritten -- and the `#@opt` marker is the claim
            # of authorship:
            #
            #   - a value the picker set, or a scaffold the user uncommented and
            #     filled in while keeping the marker, is ONE marked line: that
            #     line goes, and nothing around it. The picker's preview shows
            #     the line first, so a filled-in scaffold is deleted with the
            #     current value in view, not behind the user's back.
            #   - an UNTOUCHED scaffold -- still commented, value never filled
            #     in -- takes its doc-comment block with it: add_option wrote
            #     blank line, comments and marker line as one unit, and the
            #     comments mean nothing without the line they explain.
            #   - a line the user stripped the marker from is invisible here,
            #     which is the marker working as intended: removing it is how
            #     an adopted line is kept out of this tool's reach.
            #
            # In both cases the one blank line add_option put above the unit
            # goes too, so removing is byte-for-byte the inverse of adding --
            # checks.options holds it to exactly that.
            (pkgs.writeShellApplication {
              name = "nixarchy-opt-remove";
              runtimeInputs = [
                pkgs.coreutils
                pkgs.gnugrep
                pkgs.gnused
                pkgs.gawk
                pkgs.fzf
                config.nix.package
              ];
              text = ''
                file="''${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy/apps.nix"
                [ -f "$file" ] || { echo "no $file" >&2; exit 1; }

                if [ $# -eq 0 ]; then
                  mapfile -t paths < <(grep -o '#@opt .*' "$file" | sed 's/^#@opt //' | sort -u)
                  if [ ''${#paths[@]} -eq 0 ]; then
                    echo "No options from the picker are in $file. The Search picker adds one."
                    exit 0
                  fi
                  chosen=$(printf '%s\n' "''${paths[@]}" | fzf --multi \
                    --prompt="remove opt > " \
                    --header="tab to select several, enter to confirm" \
                    --preview "grep -F -- '#@opt '{} '$file'" \
                    --preview-window='down,3,wrap') || exit 0
                  [ -n "$chosen" ] || exit 0
                  mapfile -t picked <<< "$chosen"
                  set -- "''${picked[@]}"
                fi

                backup=$(mktemp)
                cp "$file" "$backup"
                trap 'rm -f "$backup"' EXIT
                restore() { cp "$backup" "$file"; }

                # String comparison throughout, never a regex: option paths
                # carry dots, quotes and <name> placeholders, and a path read
                # as a pattern would delete the wrong line quietly.
                remove_one() {
                  path=$1
                  tmp=$(mktemp)
                  # `if !` rather than checking $? after: this script runs under
                  # set -e, and a bare failing awk would abort before the caller
                  # could restore the backup.
                  if ! awk -v path="$path" '
                    { line[NR] = $0 }
                    END {
                      marker = "#@opt " path
                      target = 0
                      for (i = 1; i <= NR; i++) {
                        l = line[i]
                        if (length(l) >= length(marker) &&
                            substr(l, length(l) - length(marker) + 1) == marker) {
                          target = i; break
                        }
                      }
                      if (target == 0) exit 3
                      first = target
                      stripped = line[target]
                      sub(/^[ \t]*/, "", stripped)
                      if (stripped == "# " path " = ;  " marker) {
                        while (first > 1) {
                          prev = line[first - 1]
                          sub(/^[ \t]*/, "", prev)
                          if (substr(prev, 1, 1) == "#") first -= 1; else break
                        }
                      }
                      if (first > 1 && line[first - 1] == "") first -= 1
                      for (i = 1; i <= NR; i++)
                        if (i < first || i > target) print line[i]
                    }' "$file" > "$tmp"; then
                    rm -f "$tmp"
                    return 1
                  fi
                  mv "$tmp" "$file"
                }

                removed=()
                for path in "$@"; do
                  if ! remove_one "$path"; then
                    restore
                    echo "nixarchy: no option '$path' in $file. Nothing was changed." >&2
                    exit 1
                  fi
                  removed+=("$path")
                done

                [ ''${#removed[@]} -gt 0 ] || exit 0

                if ! nix-instantiate --parse "$file" >/dev/null 2>&1; then
                  restore
                  echo "nixarchy: that would have left $file unparseable. Nothing was changed." >&2
                  exit 1
                fi

                for path in "''${removed[@]}"; do
                  echo "removed $path from $file"
                done
                echo "a value that was live stays in effect until 'nixarchy-apply' rebuilds"
              '';
            })

            # Why: modules/AGENTS.md#the-answer-to-i-want-a-package-the-menu-does-not-o
            (pkgs.writeShellApplication {
              name = "nixarchy-pkg-add";
              runtimeInputs = [
                pkgs.coreutils
                pkgs.gnugrep
                pkgs.gnused
                pkgs.gawk
                pkgs.jq
                pkgs.diffutils
                config.nix.package
                cfg.package # omarchy-notification-send
              ];
              text = ''
                file="''${XDG_CONFIG_HOME:-$HOME/.config}/nixarchy/apps.nix"
                table=${appAttrTable}
                nixpkgs=${pkgs.path}
                # This generation's licence policy, baked in at build time: the
                # script and the system it can queue packages for are the same
                # generation, so this cannot go stale without the script itself
                # being replaced.
                allowunfree=${lib.boolToString (config.nixpkgs.config.allowUnfree or false)}

                # The picker is reachable through the session PATH rather than
                # runtimeInputs (same route nixarchy-apply takes to
                # nixarchy-preview), so its absence must degrade to the usage
                # text, not break the command.
                can_pick() {
                  [ -z "''${NIXARCHY_IN_PICKER:-}" ] && [ -t 0 ] && [ -t 1 ] &&
                    command -v nixarchy-search >/dev/null 2>&1
                }

                other_added=false

                # The file is a NixOS module, so the other channel's package
                # set reaches it as a module argument. Add it to the header
                # once, the same way ensure_block adds `pkgs`.
                ensure_other_arg() {
                  sed -n '/^{/{p;q}' "$file" | grep -q 'pkgsOther' && return 0
                  if sed -n '/^{/{p;q}' "$file" | grep -q 'pkgs'; then
                    sed -i -E '0,/^\{([^}]*)\}:/s/^\{([^}]*)\}:/{ pkgsOther,\1}:/' "$file"
                  else
                    sed -i -E '0,/^\{[[:space:]]*\.\.\.[[:space:]]*\}:[[:space:]]*$/s//{ pkgsOther, ... }:/' "$file"
                  fi
                  if ! sed -n '/^{/{p;q}' "$file" | grep -q 'pkgsOther'; then
                    echo "nixarchy: could not add 'pkgsOther' to the first line of $file." >&2
                    echo "Change it by hand to:  { pkgs, pkgsOther, ... }:" >&2
                    restore
                    exit 1
                  fi
                }

                # ---- the other channel (#531) -------------------------
                #
                # `--stable` and `--unstable` name a CHANNEL, not a flag the
                # tool interprets loosely: the machine follows one of them and
                # this can only mean the other. Naming the one it is already
                # on is refused rather than silently accepted, because the
                # cost of getting it wrong is a whole duplicate closure for a
                # package that was already there.
                other=false
                want_channel=""
                # --dry-run answers #495: show the diff before touching the
                # user's file. It costs nothing extra -- everything below
                # already edits $file with $backup as the pre-edit copy, so
                # dry-run's whole job is to diff those two and put $file back.
                dry_run=false
                while [ $# -gt 0 ]; do
                  case "$1" in
                    --stable)   other=true; want_channel=stable;   shift ;;
                    --unstable) other=true; want_channel=unstable; shift ;;
                    --dry-run)  dry_run=true; shift ;;
                    --) shift; break ;;
                    -*) echo "nixarchy-pkg-add: unknown option '$1'" >&2; exit 1 ;;
                    *) break ;;
                  esac
                done

                if [ "$other" = true ]; then
                  # Which channel this machine follows, read the way
                  # nixarchy-channel and the doctor read it: from the URL,
                  # which is what an update resolves, not the lock, which is
                  # only where it last landed.
                  flakedir="''${NIXARCHY_FLAKE:-/etc/nixos}"
                  mine=custom
                  if [ -r "$flakedir/flake.nix" ]; then
                    u=$(sed -nE "s/^[[:space:]]*nixpkgs\.url[[:space:]]*=[[:space:]]*\"([^\"]+)\".*/\1/p" \
                      "$flakedir/flake.nix" | head -1)
                    case "$u" in
                      *nixos-unstable*) mine=unstable ;;
                      *nixos-[0-9][0-9].[0-9][0-9]*) mine=stable ;;
                    esac
                  fi

                  # "Could not tell" is NOT "a different channel", and the
                  # difference costs a whole duplicate closure. The regex
                  # above matches the shape this project generates
                  # (`nixpkgs.url` inside an `inputs` block); the equally
                  # valid flat form `inputs.nixpkgs.url = ...` does not match
                  # it, and neither does a flake somebody has reshaped.
                  #
                  # Said out loud rather than assumed either way: refusing
                  # would block a legitimate request on a flake this tool
                  # merely cannot parse, and staying silent is how somebody
                  # ends up with two copies of the channel they were already
                  # on and no idea why the disk filled.
                  if [ "$mine" = custom ]; then
                    echo "nixarchy: cannot tell which channel this machine follows from" >&2
                    echo "  $flakedir/flake.nix, so I cannot check that --$want_channel is" >&2
                    echo "  the OTHER one. If it is the channel you are already on, this" >&2
                    echo "  adds a second copy of it that shares nothing with the first." >&2
                    echo "  ''${dim:-}nixarchy channel   reports what this machine follows.''${off:-}" >&2
                    echo >&2
                  fi

                  if [ "$mine" = "$want_channel" ]; then
                    echo "nixarchy: this machine already follows $want_channel." >&2
                    echo "  --$want_channel asks for a SECOND copy of it, from a second" >&2
                    echo "  nixpkgs, sharing nothing with the one you have. Drop the" >&2
                    echo "  flag and the package comes from the channel you are on." >&2
                    exit 1
                  fi
                fi

                if [ $# -eq 0 ]; then
                  # No arguments is not a mistake to scold, it is "show me what
                  # there is" -- which is exactly what the picker answers (#492).
                  if can_pick; then
                    exec nixarchy-search
                  fi
                  echo "usage: nixarchy-pkg-add [--stable|--unstable] [--dry-run] <nixpkgs-attribute>..." >&2
                  echo "  e.g. nixarchy-pkg-add ripgrep fd" >&2
                  echo "  or run 'nixarchy-search' to browse everything" >&2
                  echo >&2
                  echo "  --stable / --unstable take ONE package from the other" >&2
                  echo "  channel. The two share no store paths even at the same" >&2
                  echo "  version, so each one costs its whole closure." >&2
                  echo >&2
                  echo "  --dry-run shows the diff to $file without writing it." >&2
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
                missed=()
                unfree_hits=()
                to_eval=()
                report=()

                # First pass: everything answerable without evaluating nixpkgs.
                # What survives it goes into ONE evaluation below (#496) --
                # loading nixpkgs is the cost, and it is the same load whether
                # it answers for one attribute or ten, so a multi-select from
                # the picker must not pay it per selection.
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
                    report+=("$attr"$'\t'"curated"$'\t'"an Omarchy app -- enable it that way:  nixarchy-app-enable $app")
                    continue
                  fi

                  if grep -q "#@pkg $attr\$" "$file"; then
                    report+=("$attr"$'\t'"present"$'\t'"already in $file")
                    continue
                  fi

                  to_eval+=("$attr")
                done

                # Resolved against the system's own nixpkgs rather than the flake registry,
                # so the answer matches what a rebuild would actually build, and it works
                # with no network. nix-instantiate rather than `nix eval`: no pure-eval mode
                # to fight over an absolute store path, and no experimental flag to require.
                # allowUnfree only so an unfree package reports as unfree instead of
                # throwing here; nothing in this script decides your licence policy.
                #
                # Every name in one evaluation, each probed under tryEval: one
                # evaluation that died on the first bad attribute would be worse
                # than N evaluations, because a user adding five packages would
                # learn about one typo (#496). The names travel as a JSON
                # argument, not spliced into the expression.
                declare -A evalinfo
                if [ ''${#to_eval[@]} -gt 0 ]; then
                  names_json=$(printf '%s\n' "''${to_eval[@]}" | jq -R . | jq -sc .)
                  batch=$(nix-instantiate --eval --strict --json \
                    --argstr attrsJson "$names_json" --expr "
                    { attrsJson }:
                    let
                      p = import $nixpkgs { config.allowUnfree = true; };
                      probe = a:
                        let
                          path = p.lib.splitString \".\" a;
                          q = p.lib.attrByPath path null p;
                          ls = if (q.meta or { }) ? license then
                                 (if builtins.isList q.meta.license then q.meta.license else [ q.meta.license ])
                               else [ ];
                          v = {
                            inherit (q) name;
                            pname = q.pname or \"\";
                            description = q.meta.description or \"\";
                            unfree = !(builtins.all (l: if builtins.isAttrs l then (l.free or true) else true) ls);
                            broken = q.meta.broken or false;
                          };
                          r = builtins.tryEval
                            (if p.lib.hasAttrByPath path p
                             then { ok = true; } // builtins.deepSeq v v
                             else { ok = false; });
                        in if r.success then r.value else { ok = false; };
                    in builtins.listToAttrs
                      (map (a: { name = a; value = probe a; }) (builtins.fromJSON attrsJson))" \
                    2>/dev/null) || batch='{}'
                  for attr in "''${to_eval[@]}"; do
                    evalinfo[$attr]=$(jq -c --arg a "$attr" '.[$a] // { ok: false }' <<<"$batch")
                  done
                fi

                for attr in "''${to_eval[@]}"; do
                  info=''${evalinfo[$attr]}
                  if [ "$(jq -r .ok <<<"$info")" != true ]; then
                    # A name that does not resolve is a typo more often than a
                    # missing package, and the fuzzy index exists for typos: open
                    # the picker on the query instead of handing back homework
                    # (#492). Collected here, acted on after the loop, so one
                    # bad name does not sink the rest of the batch (#496).
                    missed+=("$attr")
                    report+=("$attr"$'\t'"no match"$'\t'"nixpkgs has no attribute by that name")
                    continue
                  fi

                  ensure_block

                  if [ "$other" = true ]; then
                    # From the other channel (#531). A distinct marker, not a
                    # variant of `#@pkg`: nixarchy-pkg-remove, the Search
                    # picker and the doctor all read these markers, and a row
                    # that costs a whole extra closure should not be
                    # indistinguishable from one that costs nothing.
                    ensure_other_arg
                    sed -i "/#@pkgs-end/i\\    pkgsOther.$attr  #@pkg-other $attr" "$file"
                    if ! grep -q "#@pkg-other $attr\$" "$file"; then
                      restore
                      echo "nixarchy: failed to write $attr into $file. Nothing was changed." >&2
                      exit 1
                    fi
                    other_added=true
                    added+=("$attr")
                    report+=("$attr"$'\t'"added"$'\t'"from the $want_channel channel -- it brings its own closure; the two channels share no store paths")
                    continue
                  fi

                  sed -i "/#@pkgs-end/i\\    $attr  #@pkg $attr" "$file"

                  # sed reports success when its address matches nothing, which would leave
                  # this reporting a package it never wrote. Check the line is really there.
                  if ! grep -q "#@pkg $attr\$" "$file"; then
                    restore
                    echo "nixarchy: failed to write $attr into $file. Nothing was changed." >&2
                    exit 1
                  fi
                  added+=("$attr")

                  flags=""
                  if [ "$(jq -r .unfree <<<"$info")" = true ]; then
                    if [ "$allowunfree" = true ]; then
                      flags=" [unfree -- fine here, this machine allows it]"
                    else
                      # The minority case (#497): allowUnfree defaults on, so
                      # reaching this line means somebody turned it off on
                      # purpose. Collect the pname (what allowUnfreePredicate
                      # matches on), and offer the narrow grant after the loop.
                      flags=" [unfree -- allowUnfree = false here, the rebuild will refuse it]"
                      pn=$(jq -r '.pname // ""' <<<"$info")
                      unfree_hits+=("''${pn:-$attr}")
                    fi
                  fi
                  if [ "$(jq -r .broken <<<"$info")" = true ]; then
                    flags="$flags [broken in nixpkgs -- expect the build to fail]"
                  fi
                  report+=("$attr"$'\t'"added"$'\t'"$(jq -r .name <<<"$info") -- $(jq -r '.description // ""' <<<"$info")$flags")
                done

                # One report for the whole batch, one row per name asked for
                # (#496): every outcome side by side, so a typo among five good
                # names is visible without costing the other four.
                printf '%s\n' "''${report[@]}" |
                  awk -F'\t' '{ printf "  %-28s %-9s %s\n", $1, $2, $3 }'

                # Names that resolved nowhere, with a picker available: hand them
                # to it, pre-filtered, so a typo becomes a fuzzy match. exec, so
                # this only runs once everything above is committed or reverted.
                # Without a picker (no tty, or this run IS the picker's writer,
                # where a miss is an index bug -- #492), the guidance is printed
                # instead and the exit code says something failed; whatever did
                # resolve is already committed above.
                open_missed() {
                  [ ''${#missed[@]} -gt 0 ] || return 0
                  if ! can_pick; then
                    echo "nixpkgs has no package matching: ''${missed[*]}" >&2
                    echo >&2
                    echo "Search for the right name:" >&2
                    echo "  nixarchy-search ''${missed[*]}" >&2
                    echo >&2
                    echo "If nixpkgs genuinely does not have it, draft a package from its source:" >&2
                    echo "  nixarchy pkg new <url>" >&2
                    exit 1
                  fi
                  echo "no exact match for ''${missed[*]} -- opening the picker on it"
                  # Said here, before exec, because the picker itself cannot:
                  # its miss is fzf exiting empty, and no script runs after
                  # that. This is the one moment a user has proved nixpkgs
                  # lacks a name, so the way onward is named now (#581).
                  echo "  (if nothing there matches either, nixpkgs may not have it --"
                  echo "   'nixarchy pkg new <url>' drafts a package from its source)"
                  exec nixarchy-search "''${missed[@]}"
                }

                if [ ''${#added[@]} -eq 0 ]; then
                  open_missed
                  exit 0
                fi

                # The narrow grant (#497): a commented allowUnfreePredicate
                # naming just these packages, in the user's own file, rather
                # than advice to flip the global flag. Commented, because
                # changing licence policy is the user's line to uncomment.
                # Runs before the parse check so one validation covers it.
                offer_unfree_grant() {
                  [ ''${#unfree_hits[@]} -gt 0 ] || return 0

                  if grep -q '#@unfree-allow' "$file"; then
                    # A grant already exists (ours, by its marker): grow its
                    # list in place rather than scaffold a second predicate --
                    # nixpkgs.config is a plain attrset, and two definitions of
                    # one key do not merge.
                    for pn in "''${unfree_hits[@]}"; do
                      grep -q "\"$pn\"" "$file" ||
                        sed -i "/#@unfree-allow/s/ \];/ \"$pn\" ];/" "$file"
                      if ! grep -q "\"$pn\"" "$file"; then
                        echo "  add \"$pn\" to the allowUnfreePredicate list already in $file"
                      fi
                    done
                    return 0
                  fi

                  if [ -t 0 ]; then
                    printf 'Scaffold a commented allowUnfreePredicate for %s into %s? [Y/n] ' \
                      "''${unfree_hits[*]}" "$file"
                    read -r reply || reply=n
                    case "$reply" in
                      [nN]*)
                        echo "  then allow it yourself, or set programs.nixarchy.allowUnfree = true"
                        return 0
                        ;;
                    esac
                  fi

                  names=""
                  for pn in "''${unfree_hits[@]}"; do names="$names\"$pn\" "; done
                  # printf rather than a multi-line literal: a raw
                  # newline-in-string here would lower the whole nix
                  # indented string's common indent and shift every
                  # line of the built script.
                  payload=$(printf '%s\n' \
                    "" \
                    "  # ''${unfree_hits[*]}: unfree, and this machine sets programs.nixarchy.allowUnfree" \
                    "  # = false. Uncomment the line below to allow JUST the packages named -- the" \
                    "  # narrow grant -- rather than flipping the global switch:" \
                    "  # nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [ $names];  #@unfree-allow")

                  tmp=$(mktemp)
                  awk -v payload="$payload" '
                    { print }
                    !done && /#@pkgs-end/ { print payload; done = 1 }
                  ' "$file" > "$tmp"
                  mv "$tmp" "$file"

                  if grep -q '#@unfree-allow' "$file"; then
                    echo "  scaffolded a commented allowUnfreePredicate in $file -- uncomment it to allow just ''${unfree_hits[*]}"
                  else
                    restore
                    echo "nixarchy: failed to write the allowUnfreePredicate scaffold. Nothing was changed." >&2
                    exit 1
                  fi
                }
                offer_unfree_grant

                if ! nix-instantiate --parse "$file" >/dev/null 2>&1; then
                  restore
                  echo "nixarchy: that would have left $file unparseable. Nothing was changed." >&2
                  exit 1
                fi

                # $file has been edited in place all along, with $backup as
                # the pre-edit copy every restore above already relies on --
                # so the diff nobody has seen yet is just the two of them,
                # compared now that the result is known to parse.
                #
                # NIXARCHY_IN_PICKER means fzf already collected a yes a
                # moment ago; asking again here would be a second prompt for
                # the same choice. can_pick's own guard is why: a menu pick
                # runs with no terminal attached at all, where a prompt would
                # not double-ask, it would hang.
                interactive() {
                  [ -z "''${NIXARCHY_IN_PICKER:-}" ] && [ -t 0 ] && [ -t 1 ]
                }

                if [ "$dry_run" = true ] || interactive; then
                  echo "-- $file --"
                  diff -u --label "$file (before)" --label "$file (after)" "$backup" "$file" || true
                  echo
                fi

                if [ "$dry_run" = true ]; then
                  restore
                  echo "dry run: nothing written to $file"
                  exit 0
                fi

                if interactive; then
                  printf 'Write this to %s? [Y/n] ' "$file"
                  read -r reply || reply=n
                  case "$reply" in
                    [nN]*)
                      restore
                      echo "Nothing changed."
                      exit 0
                      ;;
                  esac
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

                # The flake half, which this tool cannot do for you (#531).
                #
                # flake.nix is the user's, and adding an INPUT to it is a
                # different act from adding a line to the selection file this
                # tool owns -- nixarchy-channel's rule again: only lines this
                # project wrote get rewritten. So this prints the two lines and
                # lets the owner add them.
                #
                # Checked rather than always printed: somebody who wired it
                # once should not be told again every time.
                if [ "$other_added" = true ]; then
                  flakedir="''${NIXARCHY_FLAKE:-/etc/nixos}"
                  if ! grep -rqs 'otherChannel\.flake' "$flakedir"; then
                    echo
                    echo "One more step, in your own flake.nix -- this tool does not edit it:"
                    echo
                    echo "  inputs.nixpkgs-other.url ="
                    echo "    \"github:NixOS/nixpkgs/$( [ "$want_channel" = stable ] && echo nixos-26.05 || echo nixos-unstable )\";"
                    echo
                    echo "and, in your host configuration:"
                    echo
                    echo "  programs.nixarchy.otherChannel.flake = inputs.nixpkgs-other;"
                    echo
                    echo "Until both are there the rebuild will stop and say so."
                  fi
                fi

                echo
                echo "run 'nixarchy-apply' when you have picked everything you want"

                # Last, because exec does not come back: anything that
                # resolved is committed above before a typo's picker
                # takes over the terminal.
                open_missed
              '';
            })

            # `nixarchy pkg new <url>`: a draft derivation for software in no
            # repository (#581). The body lives in pkgs/pkg-new.sh, spliced
            # here the way flake.nix splices pkgs/doctor.sh, so a check can
            # run the raw file against stubs -- see tests/pkg-new.nix.
            (pkgs.writeShellApplication {
              name = "nixarchy-pkg-new";
              runtimeInputs = [
                pkgs.coreutils
                pkgs.gnugrep
                pkgs.gnused
                pkgs.gawk
                pkgs.nix-init
                # nix-init resolves GitHub URLs entirely on its own (proven
                # under a PATH holding nothing else), but shells out for the
                # rest of its fetchers; an undeclared command here reads as
                # "cannot draft this", not "git is missing".
                pkgs.git
                config.nix.package
              ];
              text = lib.replaceStrings [ "@nixpkgs@" ] [ "${pkgs.path}" ] (builtins.readFile ../pkgs/pkg-new.sh);
            })

            # Why: modules/AGENTS.md#search-everything-this-machine-could-install-and-r
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
                apptable=${appAttrTable}
                flatpakrows=${flatpakIndexRows}
                pkgnewrow=${pkgNewIndexRow}
                optionsjson=${optionsJsonPath}
                nixpkgs=${pkgs.path}
                walk=${./pkg-index.nix}
                flakedir="''${NIXARCHY_FLAKE:-${cfg.flake}}"
                # This generation's licence policy, baked in like the index is:
                # both are replaced together with the system generation.
                allowunfree=${lib.boolToString (config.nixpkgs.config.allowUnfree or false)}

                # The writers this picker calls fall back TO the picker on a miss
                # (#492). A row that then misses would recurse into a second
                # picker; this says "you are already inside one", so they error
                # instead -- an index row that does not resolve is an index bug.
                export NIXARCHY_IN_PICKER=1

                reindex=0
                [ "''${1:-}" = "--reindex" ] && { reindex=1; shift; }

                # One index, five tab-separated fields: kind, name, one-line summary,
                # a kind-specific fourth (an option's type; a package's flags, e.g.
                # "unfree broken curated:firefox"; empty otherwise), and the preview
                # text with its newlines escaped. The preview is carried in the line
                # rather than looked up on selection because fzf runs the preview
                # command on every keystroke, and a jq pass over 19 MB of package
                # metadata is not something to do sixty times a second.
                build_index() {
                  mkdir -p "$cache"
                  tmp=$(mktemp)

                  # Curated apps first, so they sort above the raw nixpkgs attribute of the
                  # same name. Enabling `firefox` as an app gets you programs.firefox; adding
                  # it as a package does not.
                  awk -F'\t' -v OFS='\t' '{
                    note = ($4 == "" ? "" : "\\n\\n" $4)
                    foot = ($5 == "try" ? "\\n\\nctrl-t tries it now, without installing." : "")
                    print "app", $1, $2 " (" $3 ")", "",
                      "OMARCHY APP  " $1 "\\n\\n" $2 "\\n" $3 \
                      note "\\n\\nEnabling this writes a line in your app selection:\\n  " \
                      $1 ".enable = true;" foot
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
                  #
                  # Our own walk (modules/pkg-index.nix) rather than `nix search`:
                  # verified to produce the identical row set, and it carries the
                  # meta `nix search --json` does not -- homepage, licence, unfree,
                  # broken (#493).
                  echo "  indexing nixpkgs (this takes about a minute)..." >&2
                  nix-instantiate --eval --strict --json \
                    --arg nixpkgs "$nixpkgs" "$walk" 2>/dev/null |
                    jq -r '
                      .[] |
                      [ "pkg", .attr,
                        ( ((.description // "") | gsub("[\n\t ]+"; " ") | .[0:100])
                          + (if .unfree then "  [unfree]" else "" end)
                          + (if .broken then "  [broken]" else "" end)
                        ),
                        ( (if .unfree then "unfree " else "" end)
                          + (if .broken then "broken" else "" end)
                          | sub(" $"; "")
                        ),
                        ( "NIXPKGS PACKAGE  " + .attr
                          + "\n\nversion:  " + (if .version == "" then "?" else .version end)
                          + "\nlicence:  " + (if .license == "" then "unknown" else .license end)
                          + (if .homepage == "" then "" else "\nhomepage: " + .homepage end)
                          + (if .broken then "\n\nMarked BROKEN in nixpkgs: expect the build to fail." else "" end)
                          + "\n\n" + (if .description == "" then "(no description)" else .description end)
                          + "\n\nAdding this writes it into your app selection:\n  "
                          + "environment.systemPackages = with pkgs; [ " + .attr + " ];"
                          + "\n\nctrl-t tries it now, without installing."
                        )
                      ] | @tsv' >> "$tmp"

                  # A raw attribute that the curated list already covers deserves a
                  # warning on its row: picking the APP gets the module, policies
                  # and defaults; picking the package gets a bare binary. Baked in
                  # at build time -- the curated list is as per-generation as the
                  # index (#493).
                  tmp2=$(mktemp)
                  awk -F'\t' -v OFS='\t' '
                    NR == FNR { curated[$1] = $2; next }
                    $1 == "pkg" && ($2 in curated) {
                      $4 = ($4 == "" ? "" : $4 " ") "curated:" curated[$2]
                      $5 = $5 "\\n\\nCURATED: this name is on the app list as \047" curated[$2] "\047.\\nThe app row above sets programs." curated[$2] " -- the module, with policies\\nand defaults -- where this row would add only a bare package."
                    }
                    { print }
                  ' "$apptable" "$tmp" > "$tmp2"
                  mv "$tmp2" "$tmp"

                  # Curated flatpaks and the Flathub entry point. A plain cat:
                  # these rows are already in the index's five-field shape, and
                  # they are local, so building the index still needs no network.
                  cat "$flatpakrows" >> "$tmp"

                  # The tier below those: draft a package nixpkgs lacks (#581).
                  cat "$pkgnewrow" >> "$tmp"

                  mv "$tmp" "$index"
                  readlink -f /run/current-system > "$stamp"
                }

                if [ "$reindex" = 1 ] || [ ! -s "$index" ] ||
                   [ "$(cat "$stamp" 2>/dev/null)" != "$(readlink -f /run/current-system)" ]; then
                  echo "Building the search index. This happens once per system generation." >&2
                  build_index
                fi

                # Status, at picker start rather than in the cached index (#493):
                # what is selected changes with every pick, the index once per
                # generation. Two greps and one awk pass over the index -- no
                # evaluation, and nothing per keystroke.
                #
                # "enabled" vs "queued" comes from the copy nixarchy-apply makes
                # into the flake before rebuilding: a selection that has not
                # reached the copy has not been built. Same host-dir logic as
                # nixarchy-apply. An unreadable flake dir marks everything
                # selected as queued, which is the honest claim for a machine
                # that has never applied.
                appsbase="$flakedir"
                [ -d "$flakedir/hosts/$(uname -n)" ] && appsbase="$flakedir/hosts/$(uname -n)"

                # Live (uncommented) marked lines only: kind<TAB>name per line.
                mark_live() {
                  [ -r "$1" ] || return 0
                  sed -nE "s/^[[:space:]]*[^#[:space:]].*#@pkg ([A-Za-z0-9_.-]+)[[:space:]]*$/pkg\t\1/p" "$1"
                  sed -nE "s/^[[:space:]]*[^#[:space:]].*#@ ([A-Za-z0-9_.-]+).*$/$2\t\1/p" "$1"
                }

                selected=$(mktemp)
                applied=$(mktemp)
                shown=$(mktemp)
                trap 'rm -f "$selected" "$applied" "$shown"' EXIT

                {
                  mark_live "$file" app
                  mark_live "''${file%/apps.nix}/services.nix" flatpak
                } > "$selected" || true
                {
                  mark_live "$appsbase/nixarchy/apps.nix" app
                  mark_live "$appsbase/nixarchy/services.nix" flatpak
                } > "$applied" || true

                awk -F'\t' -v OFS='\t' -v unfreeok="$allowunfree" '
                  FILENAME == ARGV[1] { sel[$0] = 1; next }
                  FILENAME == ARGV[2] { app[$0] = 1; next }
                  {
                    key = $1 "\t" $2
                    if (key in sel) {
                      st = (key in app) ? "enabled" : "queued"
                      note = (st == "enabled") \
                        ? "enabled -- selected, and nixarchy-apply has copied it into the flake" \
                        : "queued -- selected but not rebuilt; nixarchy-apply will install it"
                      $3 = "[" st "] " $3
                      $5 = $5 "\\n\\nstatus: " note
                    }
                    if ($1 == "pkg" && index($4, "unfree") && unfreeok != "true") {
                      $3 = $3 "  [disallowed]"
                      $5 = $5 "\\n\\nUNFREE, and this machine sets programs.nixarchy.allowUnfree = false:\\nthe rebuild will refuse it as it stands. nixarchy-pkg-add offers the\\nnarrow grant -- an allowUnfreePredicate naming just this package."
                    }
                    print
                  }
                ' "$selected" "$applied" "$index" > "$shown"


                # --expect makes fzf accept on ctrl-t as well as enter, and say which
                # was pressed on the first output line. The previews on pkg and app
                # rows document the key; the other two kinds have nothing to run.
                picked=$(fzf --multi \
                  --delimiter='\t' --with-nth=1,2,3 --nth=2,3 \
                  --expect=ctrl-t \
                  --preview 'printf "%b\n" {5}' \
                  --preview-window='right,58%,wrap' \
                  --prompt='nixarchy > ' \
                  --header='enter to select · ctrl-t to try · tab for several · esc to cancel' \
                  --query="''${*:-}" < "$shown") || exit 0
                key=$(printf '%s\n' "$picked" | head -n 1)
                selection=$(printf '%s\n' "$picked" | tail -n +2)
                [ -n "$selection" ] || exit 0

                # Try, not queue: run it now, in this terminal, and write nothing.
                # `nixarchy try` owns the how -- the pinned tree, the catalogue's
                # binary field, unfree -- and refuses with a reason on an app that
                # is really a NixOS module. Options and flatpaks have no package
                # attribute to run, so the picker says so itself.
                if [ "$key" = "ctrl-t" ]; then
                  while IFS=$'\t' read -r kind name _ _ _; do
                    [ -n "$kind" ] || continue
                    case "$kind" in
                      app | pkg) nixarchy try "$name" || true ;;
                      opt) echo "$name is a NixOS option -- there is nothing to run, so nothing to try" ;;
                      flatpak) echo "$name is a flatpak -- nothing to try; enable it and apply instead" ;;
                      new) echo "nothing to try yet -- picking this row asks for a source URL to draft from" ;;
                    esac
                  done <<< "$selection"
                  exit 0
                fi

                [ -f "$file" ] || { echo "no $file -- log in again to have it created" >&2; exit 1; }

                backup=$(mktemp)
                cp "$file" "$backup"
                trap 'rm -f "$backup" "$selected" "$applied" "$shown"' EXIT

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

                # One option's default or example, structured, straight out of
                # options.json -- not parsed back out of the index's preview
                # text, which flattened it for display (#581). Both fields are
                # rendered `{ _type: literalExpression, text: ... }` in modern
                # options.json; a bare JSON value is the fallback shape. Empty
                # when this system builds no manual, and every caller degrades
                # to the pre-#581 behaviour on empty.
                opt_field() {
                  [ -n "$optionsjson" ] && [ -f "$optionsjson" ] || return 0
                  jq -r --arg p "$1" --arg f "$2" \
                    '.[$p][$f]? // empty
                     | if type == "object" then (.text // tostring) else tojson end' \
                    "$optionsjson"
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
                    # Simple scalars: ask, with the default in sight (#581).
                    # /dev/tty, because stdin here is the picker's selection
                    # herestring. Empty input keeps the default by writing
                    # NOTHING -- a copied-out default is a line that reads as
                    # a choice and is not one. The patterns are anchored
                    # whole-string, so "list of string" and "null or path"
                    # fall through to the scaffold below, as they should:
                    # their values are not one prompted word.
                    "signed integer"* | "unsigned integer"* | *" bit unsigned integer"* | "positive integer"* | string | "string,"* | "string "* | path | "path,"* | "absolute path"*)
                      default=$(opt_field "$path" default || true)
                      default=''${default//$'\n'/ }
                      if ! read -r -p "$path [''${default:-no default}] = " value < /dev/tty; then
                        return 0
                      fi
                      if [ -z "$value" ]; then
                        echo "kept the default for $path -- nothing written"
                        return 0
                      fi
                      # A string or path needs Nix quotes; typing them is the
                      # sort of homework this prompt exists to remove. Already
                      # quoted input passes through untouched.
                      case "$type" in
                        string* | path* | "absolute path"*)
                          case "$value" in
                            \"*) ;;
                            *) value="\"''${value//\"/\\\"}\"" ;;
                          esac
                          ;;
                      esac
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
                  # expression to you -- seeded with the option's own example (or its
                  # default, when there is no example) as a starting shape to edit,
                  # rather than a shape to invent (#581).
                  #
                  # The seed lines are COMMENTS above the marked line, and the marked
                  # line itself keeps the exact `# <path> = ;  #@opt <path>` bytes:
                  # nixarchy-opt-remove keys its walk up the comment block on that
                  # shape, which is what lets a scaffold leave byte for byte
                  # (checks.options asserts it, seed included).
                  seed=$(opt_field "$path" example || true)
                  seedsrc=example
                  if [ -z "$seed" ]; then
                    seed=$(opt_field "$path" default || true)
                    seedsrc=default
                  fi
                  {
                    printf '\n'
                    grep -P "^opt\t\Q$path\E\t" "$index" | head -1 |
                      cut -f5 | sed 's/\\n/\n/g' | sed 's/^/  # /'
                    if [ -n "$seed" ]; then
                      printf '  #\n'
                      printf "  # a starting shape, from the option's %s -- yours to edit:\n" "$seedsrc"
                      printf '%s\n' "$seed" | awk -v p="$path" 'NR == 1 { $0 = p " = " $0 } { print "  #   " $0 }'
                    fi
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

                # Why: modules/AGENTS.md#ask-flathub-org-directly
                flathub_search() {
                  local query hits picked id line
                  # /dev/tty, because stdin here is the picker's selection --
                  # this function is called from inside `done <<< "$selection"`,
                  # which has already consumed it. Without this the read hits
                  # EOF, `|| return 0` fires, and the row that exists for
                  # "the other three sources have failed you" silently does
                  # NOTHING. It failed quietly, which is why it survived (#596).
                  read -r -p "Search Flathub for: " query < /dev/tty || return 0
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

                pkg_batch=()
                while IFS=$'\t' read -r kind name _ type _; do
                  [ -n "$kind" ] || continue
                  case "$kind" in
                    app) nixarchy-app-enable "$name" && changed=1 ;;
                    # Collected, not dispatched one by one: pkg-add resolves its
                    # names in a single nixpkgs evaluation and sends a single
                    # notification, so a multi-select must arrive as one call
                    # to get one of each rather than N (#496).
                    pkg) pkg_batch+=("$name") ;;
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
                    # Software in no repository at all (#581). The binary, not
                    # `nixarchy pkg new`: the same session-PATH route every
                    # other writer in this case uses, without leaning on the
                    # dispatcher's routing. /dev/tty, because stdin here is
                    # the selection herestring and a bare read would eat the
                    # next picked row. `|| true`: a draft that fails to build
                    # is a reported outcome, not a reason to abort the loop.
                    # No changed=1 -- nixarchy-pkg-new validates its own write
                    # and prints its own guidance.
                    new)
                      if read -r -p "Source URL (e.g. https://github.com/someone/tool): " url < /dev/tty; then
                        [ -z "$url" ] || nixarchy-pkg-new "$url" || true
                      fi
                      ;;
                  esac
                done <<< "$selection"

                if [ ''${#pkg_batch[@]} -gt 0 ]; then
                  # Judged by the file, not the exit code: pkg-add exits
                  # nonzero when ANY name missed, and inside the picker a miss
                  # is an index bug -- but the names that did resolve are
                  # committed, and they still deserve the summary below.
                  pre=$(cksum < "$file")
                  nixarchy-pkg-add "''${pkg_batch[@]}" || true
                  [ "$pre" = "$(cksum < "$file")" ] || changed=1
                fi

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

            # `nixarchy box <subcommand>`. Its own file for the same reason as
            # dev-init.nix and microvm.nix above: `checks.box-template` (#258)
            # has to run the real command. See pkgs/box.nix for what it does
            # and why -- in particular why it never resolves distrobox through
            # a /nix/store path.
            (pkgs.callPackage ../pkgs/box.nix { })

            # Why: modules/AGENTS.md#one-name-for-the-commands-this-repo-adds-and-a-way
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
                      remove) shift 2; exec nixarchy-pkg-remove "$@" ;;
                      new) shift 2; exec nixarchy-pkg-new "$@" ;;
                      undraft) shift 2; exec nixarchy-pkg-undraft "$@" ;;

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
                  # Without this row `nixarchy try foo` falls through to
                  # `exec omarchy try ...` and dies as "Unknown Omarchy command"
                  # -- omarchy's own dispatcher discovers only omarchy-*
                  # siblings, and nixarchy-try is not one.
                  #
                  # It is the Search picker's ctrl-t path too, so the whole
                  # feature is unreachable without it. Both halves shipped
                  # green: the picker's check greps that nixarchy-search SAYS
                  # `nixarchy try `, which is the call site, not the route.
                  # checks.options now asserts the route.
                  try) shift; exec nixarchy-try "$@" ;;
                  vm) shift; exec nixarchy-vm "$@" ;;
                  box) shift; exec nixarchy-box "$@" ;;

                  # The rest of them (#538). Every one of these was shipped,
                  # documented, and unreachable: without a row here the command
                  # reaches `exec omarchy "$@"`, and Omarchy's own dispatcher
                  # builds `omarchy-$(join_words ...)` and globs `omarchy-*`
                  # only -- so `nixarchy channel stable` died as "Unknown
                  # Omarchy command: omarchy channel stable".
                  #
                  # `try` was found by hand and fixed alone. Nothing generalised
                  # it, and the same bug was sitting in ten siblings. What makes
                  # that not happen again is not this list -- it is
                  # checks.options deriving the list from the commands' own
                  # `# omarchy:examples=nixarchy <verb>` headers and asserting
                  # every one of them routes. A command declares the verb it
                  # answers to; the check makes the dispatcher agree.
                  android) shift; exec nixarchy-android "$@" ;;
                  ask) shift; exec nixarchy-ask "$@" ;;
                  channel) shift; exec nixarchy-channel "$@" ;;
                  local-ai) shift; exec nixarchy-local-ai "$@" ;;
                  preview) shift; exec nixarchy-preview "$@" ;;
                  rollback) shift; exec nixarchy-rollback "$@" ;;
                  unfreeze) shift; exec nixarchy-unfreeze "$@" ;;

                  # Two-word verbs, in the shape `pkg`, `app` and `dev` already
                  # use. These are the ones a route check that matches
                  # `^ *<verb>)` cannot see, which is why the first version of
                  # that check passed over them.
                  #
                  # No bare fallthrough on the inner case: `nixarchy config`
                  # with no second word drops out of the inner `case` and
                  # reaches `exec omarchy "$@"`, which is the right answer --
                  # Omarchy has its own `config` and this port does not take the
                  # word from it.
                  config)
                    case "''${2:-}" in
                      repo) shift 2; exec nixarchy-config-repo "$@" ;;
                    esac
                    ;;
                  home)
                    case "''${2:-}" in
                      backup) shift 2; exec nixarchy-home-backup "$@" ;;
                    esac
                    ;;
                  reinstall)
                    case "''${2:-}" in
                      iso) shift 2; exec nixarchy-reinstall-iso "$@" ;;
                    esac
                    ;;
                  ""|--help|-h|help)
                    cat <<'USAGE'
                nixarchy -- the Omarchy desktop, vendored for NixOS.

                Commands this port adds:

                  nixarchy search [query]     Every package, NixOS option and app, in one picker
                  nixarchy pkg add <attr>     Add a nixpkgs package to the app selection
                  nixarchy pkg remove [attr]  Take one out again (no argument picks interactively)
                  nixarchy pkg new <url>      Draft a derivation for software in no repository
                  nixarchy pkg undraft [name] Take a draft's line out again (the draft file stays)
                  nixarchy app enable <id>    Select an app from the curated list
                  nixarchy app disable <id>   Deselect one
                  nixarchy app remove         Pick apps, packages and options to remove
                  nixarchy apply              Copy the selection into your flake and rebuild
                  nixarchy dev init <preset>  Scaffold a devenv project here (no argument lists them)
                  nixarchy try <app|attr>     Run something once without installing it
                  nixarchy vm <subcommand>    Disposable NixOS MicroVMs -- 'nixarchy vm help'
                  nixarchy box <subcommand>   distrobox, for software NixOS will not run -- 'nixarchy box help'
                  nixarchy doctor             What this machine needs to run nixarchy

                This machine:

                  nixarchy channel [stable|unstable]  Which nixpkgs this machine follows
                  nixarchy preview            Boot this configuration in a VM before switching
                  nixarchy rollback           Go back to an earlier system generation
                  nixarchy unfreeze           Let this machine receive updates again
                  nixarchy config repo        Put /etc/nixos in git, with a remote and CI
                  nixarchy home backup        Back up the desktop configuration in your home
                  nixarchy reinstall iso      Build an image that reinstalls this machine
                  nixarchy android            Connect an Android phone over Wi-Fi, for scrcpy
                  nixarchy ask                Ask the default agent, with the right skill chosen
                  nixarchy local-ai           Set up the local language model

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

                # Why: modules/AGENTS.md#where-the-selection-lands
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

                # Why: modules/AGENTS.md#a-flake-cannot-read-a-file-outside-its-own-tree-so
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

                # Draft derivations from `nixarchy pkg new` ride along:
                # apps.nix names them as ./packages/<name>.nix, a path
                # relative to the COPY, so they must sit beside it or the
                # uncommented line fails evaluation with "path does not
                # exist". Copies accumulate and are never deleted here --
                # removing a draft from the flake is an edit to a tree the
                # user owns, not this tool's call.
                if [ -d "$srcdir/packages" ]; then
                  mkdir -p "$base/nixarchy/packages"
                  for src in "$srcdir"/packages/*.nix; do
                    [ -f "$src" ] || continue
                    dst="$base/nixarchy/packages/$(basename "$src")"
                    if [ -f "$dst" ] && diff -q "$src" "$dst" >/dev/null; then
                      continue
                    fi
                    cp "$src" "$dst"
                    copied="$copied packages/$(basename "$src")"
                  done
                fi

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

                # Why: modules/AGENTS.md#stage-what-was-written-or-a-flake-in-a-git-worktre
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

                # Why: modules/AGENTS.md#whether-anything-in-the-flake-actually-imports-it
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

                # The offer, at the one moment somebody actually wants it
                # (#488): the selection is copied, the switch is the next
                # keypress, and a look before leaping costs a question.
                #
                # `command -v`, because nixarchy-preview ships in the omarchy
                # package rather than in this script's runtimeInputs -- it is
                # reached through the session PATH writeShellApplication
                # prepends to, and on a machine without the package the offer
                # must vanish rather than break the apply.
                #
                # `|| true`: a refused preflight (or a preview closed with a
                # nonzero status) must land back at the switch question, not
                # kill the apply under set -e.
                # `|| reply=""` on every prompt, because EOF is not a crash.
                #
                # `read` returns non-zero at end of input, and under
                # writeShellApplication's `set -e` that KILLS the script. So the
                # moment this file grew a second prompt, `echo n | nixarchy-apply`
                # -- one line, two reads -- started exiting 1: the first read took
                # the "n", the second hit EOF. checks.session drives exactly that
                # and went red on it.
                #
                # Treating EOF as an empty answer is also the right behaviour
                # rather than a test accommodation: a piped or non-interactive
                # apply should decline to switch, not die halfway through.
                if command -v nixarchy-preview >/dev/null 2>&1; then
                  read -r -p "Preview in a VM first? [y/N] " reply || reply=""
                  case "$reply" in
                    [yY]*) nixarchy-preview || true ;;
                  esac
                fi

                read -r -p "Build and switch now? [y/N] " reply || reply=""
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
    ))
  ];
}
