# `nixarchy secret <verb>` -- the five manual steps in
# docs/manual/remote-desktop.md, as one command.
#
# Its own file for the same reason as pkgs/dev-init.nix, pkgs/microvm.nix and
# pkgs/box.nix: tests/menu-verbs.nix has to read the verbs out of the command
# the menu actually execs, which means the command has to be a package.
#
# WHAT THIS IS BUILT ON, AND WHY IT IS NOT agenix. modules/secrets.md has the
# long version; the short one is that hypr-rdp reads its password only from
# inside a TOML file, `sops.templates` is the upstreamed shim that puts it
# there, and agenix has no templating at all. `sops edit` opens $EDITOR
# exactly as `agenix -e` does, so nothing about the flow the user sees depends
# on that choice.
#
# THREE RULES THIS FILE MUST NOT BREAK:
#
# 1. The declaration goes in `hosts/<host>/configuration.nix`, and this
#    command never writes it. `nixarchy-apply` copies ~/.config/nixarchy/*.nix
#    into the flake and `git add -A`s them, so a secret declared there is
#    carried into a directory one level deeper than the `./secrets.yaml` it
#    names. We print the two lines; the user places them.
#
# 2. The host's age identity never leaves root. Deriving it costs a read of
#    /etc/ssh/ssh_host_ed25519_key, so every sops call that has to DECRYPT a
#    system secret goes through `hostSops` below -- a root-side wrapper that
#    does the conversion in its own command substitution. Writing
#    `sudo env SOPS_AGE_KEY="$(sudo ssh-to-age ...)" sops ...` instead would
#    put the host's private identity in argv, and /proc/*/cmdline is
#    world-readable to every process on the machine.
#
# 3. A decrypted value goes to the clipboard through a PIPE. It is never
#    assigned to a variable, written to a file, or passed as an argument.
{
  lib,
  writeShellApplication,
  writeText,
  coreutils,
  gnugrep,
  gnused,
  gawk,
  jq,
  fzf,
  sops,
  ssh-to-age,
  age,
  wl-clipboard,
}:
let
  # sops, holding the host's own key. Root-only by construction: the
  # conversion happens inside this script's own process, so the identity
  # exists nowhere a non-root process can read it. See rule 2 above.
  hostSops = writeShellApplication {
    name = "nixarchy-secret-host-sops";
    runtimeInputs = [
      sops
      ssh-to-age
      coreutils
    ];
    text = ''
      key=/etc/ssh/ssh_host_ed25519_key
      if [ ! -r "$key" ]; then
        echo "nixarchy secret: cannot read $key." >&2
        echo "  This has to run as root: sops decrypts a system secret with" >&2
        echo "  the machine's own SSH host key and with nothing else." >&2
        exit 1
      fi
      # Command substitution inside a process that is already root. The value
      # is exported to the one child and to nothing else.
      SOPS_AGE_KEY=$(ssh-to-age -private-key -i "$key")
      export SOPS_AGE_KEY
      exec sops "$@"
    '';
  };

  # What the machine actually declares, and what names it -- read out of the
  # evaluated configuration rather than out of a list somebody maintains.
  # §4: a hand-maintained list fails OPEN, and this repository found three
  # doing exactly that in one day.
  #
  # `refs` answers "what uses this secret". hypr-rdp is the shape to match:
  # `passwordSecret` is a string NAMING a sops.secrets attribute, so a
  # reference is an option whose name ends in Secret and whose value is the
  # secret's name. The other shape is a template that renders it, and that one
  # is found by the placeholder rather than by the name -- sops.templates
  # carry `config.sops.placeholder.<name>`, which is a hash, not the name.
  discover = writeText "nixarchy-secret-discover.nix" ''
    cfg:
    let
      tryV = f: let r = builtins.tryEval f; in if r.success then r.value else null;

      secrets = builtins.attrNames (cfg.sops.secrets or { });
      templates = cfg.sops.templates or { };

      # Bounded on purpose: programs.nixarchy is the surface this repository
      # owns and the only one whose naming convention we can rely on. A
      # reference written in the user's OWN configuration is found textually
      # by the caller instead, and `where` labels the two differently -- a
      # derived answer and a grep are not the same claim.
      walk =
        depth: path: v:
        if depth > 8 then
          [ ]
        else if builtins.isAttrs v then
          (
            if v ? outPath || v ? _type then
              [ ]
            else
              builtins.concatMap (
                n: walk (depth + 1) (if path == "" then n else path + "." + n) (tryV v.''${n})
              ) (builtins.attrNames v)
          )
        else if builtins.isString v then
          [ { p = path; v = v; } ]
        else
          [ ];

      # programs.nixarchy.SERVICES, not programs.nixarchy. Two reasons, and
      # the second is the one that bites: every *Secret option this repository
      # has or is likely to grow belongs to a bundled service, and walking the
      # whole of programs.nixarchy forces `apps.nixpkgsConfig`, whose default
      # is `{ inherit (pkgs.config) allowUnfree allowUnfreePredicate; }` and
      # throws `attribute 'allowUnfreePredicate' missing` on a pkgs that has
      # not set one. `builtins.tryEval` does NOT catch that -- it catches
      # `throw` and `assert`, not a missing attribute -- so tryV around the
      # access is no protection at all. Verified live: with the root at
      # programs.nixarchy this expression aborted rather than returning
      # anything.
      named = builtins.filter (e: (builtins.match ".*Secret" e.p) != null) (
        walk 0 "programs.nixarchy.services" (tryV (cfg.programs.nixarchy.services or { }))
      );

      refsFor =
        name:
        (map (e: "option " + e.p) (builtins.filter (e: e.v == name) named))
        ++ (
          let
            ph = tryV (cfg.sops.placeholder.''${name} or null);
          in
          if ph == null || !(builtins.isString ph) then
            [ ]
          else
            map (t: "template " + t) (
              builtins.filter (
                t:
                let
                  c = tryV (templates.''${t}.content or "");
                in
                # builtins.split rather than builtins.match: a template's
                # content is a whole config file, and whether `.` matches a
                # newline is not something to bet a discovery tool on.
                c != null && builtins.isString c && builtins.length (builtins.split ph c) > 1
              ) (builtins.attrNames templates)
            )
        );
    in
    builtins.listToAttrs (
      map (n: {
        name = n;
        value = {
          path = tryV (cfg.sops.secrets.''${n}.path or null);
          owner = tryV (cfg.sops.secrets.''${n}.owner or null);
          refs = refsFor n;
        };
      }) secrets
    )
  '';
in
writeShellApplication {
  name = "nixarchy-secret";

  # §7: writeShellApplication PREPENDS this to PATH rather than replacing it,
  # so `sudo` still resolves through /run/wrappers/bin -- the only place it
  # can, since a sudo out of the store is not setuid. `nix` is left to the
  # machine's own PATH for the same reason nixarchy-config-repo leaves it:
  # the CLI and the daemon want to be the pair the system installed.
  runtimeInputs = [
    coreutils
    gnugrep
    gnused
    gawk
    jq
    fzf
    sops
    ssh-to-age
    age
    wl-clipboard
  ];

  # jq programs reference their --arg bindings as $n inside single quotes,
  # which is the documented way to pass a shell value into jq safely and
  # exactly what SC2016 exists to warn about elsewhere.
  excludeShellChecks = [ "SC2016" ];

  text = ''
    FLAKE=''${NIXARCHY_FLAKE:-/etc/nixos}
    HOST=$(cat /proc/sys/kernel/hostname)
    HOST_KEY=/etc/ssh/ssh_host_ed25519_key
    SYS_STORE="$FLAKE/hosts/$HOST/secrets.yaml"
    POLICY="$FLAKE/.sops.yaml"

    # NOT ~/.config/nixarchy: nixarchy-apply copies that directory into the
    # flake, and the flake gets committed and pushed. NOT anywhere on
    # nixarchy-home-backup's allowlist either -- that list is four paths
    # chosen not to contain secrets, and this would be the fifth.
    USER_DIR="''${XDG_DATA_HOME:-$HOME/.local/share}/nixarchy/secrets"
    USER_STORE="$USER_DIR/user.yaml"
    USER_KEY="$USER_DIR/identity.txt"

    HOST_SOPS=${lib.getExe hostSops}
    DISCOVER=${discover}

    bold=$(printf '\033[1m')
    dim=$(printf '\033[2m')
    red=$(printf '\033[31m')
    yellow=$(printf '\033[33m')
    green=$(printf '\033[32m')
    off=$(printf '\033[0m')

    say()  { printf '%s\n' "$*"; }
    step() { printf '\n%s%s%s\n' "$bold" "$*" "$off"; }
    ok()   { printf '  %s+%s %s\n' "$green" "$off" "$*"; }
    warn() { printf '  %s!%s %s\n' "$yellow" "$off" "$*"; }
    fail() { printf '  %sx%s %s\n' "$red" "$off" "$*" >&2; }

    usage() {
    cat <<'USAGE'
    nixarchy secret -- passwords, keys and tokens this machine can use.

      nixarchy secret new [--user] <name>     create one, and open the editor
      nixarchy secret edit [--user]           change one
      nixarchy secret list                    what exists, and what reads it
      nixarchy secret where <name>            what names this one
      nixarchy secret copy [<name>]           put one on the clipboard
      nixarchy secret remove [--user] <name>  take one out of the store

    Two kinds, and the difference between them is the whole design:

      system   decrypted by root into /run/secrets, mode 0400, for a SERVICE
               to read. Encrypted to this machine's SSH host key.
      --user   decrypted by you, to the clipboard, never to disk. Encrypted
               to an age identity of your own.

    Making system secrets readable by you instead would mean every process
    running as you -- a browser, a dependency in a dev shell -- can read every
    secret on the machine. That is why there are two kinds and not one.

    THIS MACHINE ONLY. Sharing a secret with a second machine means adding its
    recipient to .sops.yaml and rekeying, which is sops' own job and its
    sharpest edge: see `sops updatekeys` and
    https://github.com/getsops/sops#adding-and-removing-keys
    USAGE
    }

    # ---- the ordering constraint, met once rather than discovered ----------
    #
    # modules/secrets.md: a machine's SSH host key is generated on FIRST BOOT,
    # and without services.openssh there is never one at all. sops.age
    # .sshKeyPaths then evaluates to [] and declaring any secret fails the
    # rebuild with upstream's own message. That is a good failure -- loud,
    # early, nothing starts -- and a terrible way to meet it, so this says it
    # first.
    require_host_key() {
      [ -r "$HOST_KEY.pub" ] && return 0
      fail "This machine has no SSH host key, so nothing can encrypt to it."
      say  ""
      say  "  A system secret is encrypted to $HOST_KEY,"
      say  "  which NixOS generates only when sshd is enabled, and only on the"
      say  "  first boot after that. Without it, declaring a secret fails the"
      say  "  rebuild at evaluation time with sops-nix's own message:"
      say  ""
      say  "    ''${dim}No key source configured for sops. Either set"
      say  "    services.openssh.enable or set sops.age.keyFile...''${off}"
      say  ""
      say  "  Add this to ''${bold}$FLAKE/hosts/$HOST/configuration.nix''${off},"
      say  "  rebuild, then run this again:"
      say  ""
      say  "    services.openssh.enable = true;"
      say  ""
      say  "  Or leave sshd off and use ''${bold}nixarchy secret new --user <name>''${off},"
      say  "  which encrypts to an identity of your own instead. A user secret"
      say  "  cannot be handed to a system service, and that is the trade."
      return 1
    }

    # .sops.yaml is the user's policy file, and it may already describe other
    # hosts or name their own key as a second recipient. Written whole when it
    # is absent; when it exists and does not cover this host, the block is
    # PRINTED rather than spliced in -- a YAML edit made by pattern-matching
    # is how a creation rule silently stops matching.
    ensure_policy() {
      local recipient
      recipient=$(ssh-to-age -i "$HOST_KEY.pub")

      if [ ! -e "$POLICY" ]; then
        step "Writing $POLICY"
        {
          printf '%s\n' "# Which recipients can decrypt which file. Written by nixarchy secret."
          printf '%s\n' "# Add your own age key as a second recipient here if you want to edit"
          printf '%s\n' "# this host's secrets from another machine, then run"
          printf '%s\n' "#   sops updatekeys hosts/$HOST/secrets.yaml"
          printf '%s\n' "keys:"
          printf '%s\n' "  - &$HOST $recipient"
          printf '%s\n' "creation_rules:"
          printf '%s\n' "  - path_regex: hosts/$HOST/secrets\\.yaml\$"
          printf '%s\n' "    key_groups:"
          printf '%s\n' "      - age:"
          printf '%s\n' "          - *$HOST"
        } | sudo tee "$POLICY" >/dev/null
        ok "policy written, with this host as the only recipient"
        return 0
      fi

      if grep -q "hosts/$HOST/secrets" "$POLICY"; then
        ok "$POLICY already covers this host"
        return 0
      fi

      fail "$POLICY exists and has no rule for hosts/$HOST/secrets.yaml."
      say  ""
      say  "  Not edited for you: this file is your policy, and a rule spliced"
      say  "  in by pattern-matching is one that can silently stop matching."
      say  "  Add this to it, beside the keys you already have:"
      say  ""
      say  "    keys:"
      say  "      - &$HOST $recipient"
      say  "    creation_rules:"
      say  "      - path_regex: hosts/$HOST/secrets\\.yaml\$"
      say  "        key_groups:"
      say  "          - age:"
      say  "              - *$HOST"
      say  ""
      return 1
    }

    # ---- the user half -----------------------------------------------------
    #
    # sops decrypts to /run/secrets as root:root 0400, which is right for a
    # service and useless for a person. So: a separate identity, and a store
    # the user owns.
    ensure_user_identity() {
      mkdir -p "$USER_DIR"
      chmod 700 "$USER_DIR"

      if [ ! -f "$USER_KEY" ]; then
        step "Creating your own age identity"
        age-keygen -o "$USER_KEY" 2>/dev/null
        chmod 600 "$USER_KEY"
        ok "$USER_KEY"
        warn "This file is the ONLY thing that can read your user secrets."
        say  "    It is deliberately outside the configuration repository and"
        say  "    outside ''${bold}nixarchy home backup''${off}'s allowlist, because both of"
        say  "    those are pushed to a git remote. Copy it somewhere safe"
        say  "    yourself: if you lose it the store is unreadable, and there"
        say  "    is no recovery."
      fi

      local recipient
      recipient=$(age-keygen -y "$USER_KEY")
      {
        printf '%s\n' "# Written by nixarchy secret. sops walks up from the file it is"
        printf '%s\n' "# editing, so this governs user.yaml beside it and nothing else."
        printf '%s\n' "creation_rules:"
        printf '%s\n' "  - path_regex: user\\.yaml\$"
        printf '%s\n' "    key_groups:"
        printf '%s\n' "      - age:"
        printf '%s\n' "          - $recipient"
      } > "$USER_DIR/.sops.yaml"
    }

    # ---- reading what exists -----------------------------------------------
    #
    # sops encrypts VALUES and leaves keys in plaintext, so the names in a
    # store can be read with no identity at all. That is what makes `list`
    # work on a machine whose flake will not evaluate, and it is also why
    # modules/secrets.md says to keep anything sensitive out of a name.
    names_in_store() {
      [ -r "$1" ] || return 0
      grep -oE '^[A-Za-z0-9_][A-Za-z0-9_.-]*:' "$1" 2>/dev/null \
        | sed 's/:$//' \
        | grep -vx sops || true
    }

    # config.sops.secrets, out of the real configuration. Empty output means
    # "could not evaluate", which the caller reports differently from "none
    # declared" -- those are very different answers, and reporting the first
    # as the second is where a discovery tool starts lying.
    declared_json() {
      nix eval --json --apply "$(cat "$DISCOVER")" \
        "$FLAKE#nixosConfigurations.$HOST.config" 2>/dev/null || true
    }

    # ---- verbs --------------------------------------------------------------

    do_new() {
      local kind=$1 name=$2
      if [ "$kind" = user ]; then
        ensure_user_identity
        step "Opening your user secret store"
        say  "  Add a line ''${bold}$name: your-value''${off} and save."
        SOPS_AGE_KEY_FILE="$USER_KEY" sops edit "$USER_STORE"
        ok "encrypted to your identity, at $USER_STORE"
        say ""
        say "  Read it back with: ''${bold}nixarchy secret copy $name''${off}"
        return 0
      fi

      require_host_key || return 1
      sudo mkdir -p "$FLAKE/hosts/$HOST"
      ensure_policy || return 1

      step "Opening $SYS_STORE"
      say  "  Plain YAML until you save; sops encrypts it on the way out. Add:"
      say  ""
      say  "    ''${bold}$name: your-value''${off}"
      say  ""
      sudo --preserve-env=EDITOR "$HOST_SOPS" edit "$SYS_STORE"

      # The one step this command deliberately does not take for you, and
      # exactly where it has to go. See rule 1 in this file's header.
      step "One line left, and it is yours to place"
      say  "  In ''${bold}$FLAKE/hosts/$HOST/configuration.nix''${off}:"
      say  ""
      say  "    sops.secrets.$name.sopsFile = ./secrets.yaml;"
      say  ""
      say  "  ''${bold}Not''${off} in ~/.config/nixarchy/*.nix. nixarchy-apply copies those"
      say  "  into $FLAKE/hosts/$HOST/nixarchy/, so a relative ./secrets.yaml"
      say  "  written there resolves one directory too deep."
      say  ""
      say  "  Then stage the encrypted file and rebuild. A flake in a git"
      say  "  worktree sees only tracked files, so an unstaged secrets.yaml"
      say  "  does not exist as far as evaluation is concerned:"
      say  ""
      say  "    sudo git -C $FLAKE add hosts/$HOST/secrets.yaml"
      say  "    nixarchy apply"
    }

    do_edit() {
      local kind=$1
      if [ "$kind" = user ]; then
        [ -f "$USER_STORE" ] || {
          fail "no user secrets yet. Make one: nixarchy secret new --user <name>"
          return 1
        }
        ensure_user_identity
        SOPS_AGE_KEY_FILE="$USER_KEY" sops edit "$USER_STORE"
        return 0
      fi
      require_host_key || return 1
      [ -f "$SYS_STORE" ] || {
        fail "no system secrets yet. Make one: nixarchy secret new <name>"
        return 1
      }
      sudo --preserve-env=EDITOR "$HOST_SOPS" edit "$SYS_STORE"
    }

    do_remove() {
      local kind=$1 name=$2
      if [ "$kind" = user ]; then
        [ -f "$USER_STORE" ] || { fail "no user secrets to remove from"; return 1; }
        ensure_user_identity
        if SOPS_AGE_KEY_FILE="$USER_KEY" sops unset "$USER_STORE" "[\"$name\"]" 2>/dev/null; then
          ok "removed $name"
          return 0
        fi
        fail "could not remove it automatically."
        say  "  Open the store and delete the line: ''${bold}nixarchy secret edit --user''${off}"
        return 1
      fi

      require_host_key || return 1
      if sudo "$HOST_SOPS" unset "$SYS_STORE" "[\"$name\"]" 2>/dev/null; then
        ok "removed $name from $SYS_STORE"
        warn "Anything still declaring sops.secrets.$name fails the next rebuild."
        return 0
      fi
      fail "could not remove it automatically."
      say  "  Open the store and delete the line: ''${bold}nixarchy secret edit''${off}"
      return 1
    }

    # ---- copy: to the clipboard, never to disk ------------------------------
    #
    # The plaintext exists only in the pipe between sops and wl-copy. It is
    # never assigned to a variable (which `set -x`, a crash dump or an
    # exported environment could expose), never written to a temporary file,
    # and never passed as an argument.
    #
    # THE HOLE, NAMED (§3): Omarchy's shell records what you copy in
    # ~/.local/state/omarchy/clipboard-history.json, in plaintext. Nothing
    # here can prevent that -- the recorder is a Wayland clipboard watcher in
    # the shell, and a wl-copy that opts out of it does not exist.
    # `--paste-once` narrows the clipboard itself to a single paste; the
    # history entry is what the warning below is about, and
    # docs/manual/secrets.md says the same thing where a user will read it.
    copy_value() {
      local kind=$1 name=$2
      if [ "$kind" = user ]; then
        ensure_user_identity
        SOPS_AGE_KEY_FILE="$USER_KEY" sops -d --extract "[\"$name\"]" "$USER_STORE" \
          | wl-copy --paste-once
      else
        require_host_key || return 1
        sudo "$HOST_SOPS" -d --extract "[\"$name\"]" "$SYS_STORE" \
          | wl-copy --paste-once
      fi
      ok "$name is on the clipboard, and clears itself after one paste."
      warn "Omarchy records the clipboard: this value is now in plaintext in"
      say  "    ~/.local/state/omarchy/clipboard-history.json until you clear it."
    }

    # Every row the picker can offer, as "<kind><tab><name>".
    all_rows() {
      local n
      while IFS= read -r n; do
        [ -n "$n" ] && printf 'system\t%s\n' "$n"
      done < <(names_in_store "$SYS_STORE")
      while IFS= read -r n; do
        [ -n "$n" ] && printf 'user\t%s\n' "$n"
      done < <(names_in_store "$USER_STORE")
    }

    do_copy() {
      local name=''${1:-} kind="" rows selection answer

      if [ -n "$name" ]; then
        if names_in_store "$USER_STORE" | grep -qx "$name"; then
          kind=user
        elif names_in_store "$SYS_STORE" | grep -qx "$name"; then
          kind=system
        else
          fail "no secret called '$name'. Try: nixarchy secret list"
          return 1
        fi
        copy_value "$kind" "$name"
        return
      fi

      rows=$(all_rows)
      [ -n "$rows" ] || {
        fail "no secrets on this machine yet. Make one: nixarchy secret new <name>"
        return 1
      }

      selection=$(printf '%s\n' "$rows" \
        | awk -F'\t' '{ printf "%-8s %s\n", $1, $2 }' \
        | fzf --prompt='copy secret > ' \
              --header='system = decrypted by root, asks for sudo    user = yours' \
              --height=40% --reverse) || return 0
      [ -n "$selection" ] || return 0

      kind=$(printf '%s' "$selection" | awk '{print $1}')
      name=$(printf '%s' "$selection" | awk '{print $2}')

      # #596: a `read` reached from a picker's dispatch reads whatever the
      # loop is feeding it, not the keyboard, and fails silently at EOF. Every
      # prompt here names the terminal, and tests/options.nix asserts it for
      # this command as well as for nixarchy-search.
      if [ "$kind" = system ]; then
        answer=""
        read -r -p "  $name is a system secret and needs sudo. Copy it? [y/N] " answer < /dev/tty
        case "$answer" in
          [yY]*) ;;
          *) say "  nothing copied."; return 0 ;;
        esac
      fi
      copy_value "$kind" "$name"
    }

    do_list() {
      local json declared sysnames usernames n refs missing

      json=$(declared_json)

      step "Declared in this machine's configuration"
      if [ -z "$json" ]; then
        warn "could not evaluate $FLAKE#nixosConfigurations.$HOST."
        say  "    Falling back to the names in the encrypted files, which sops"
        say  "    leaves in plaintext. That says what EXISTS and nothing about"
        say  "    what the machine does with it."
      else
        declared=$(printf '%s' "$json" | jq -r 'keys[]')
        if [ -z "$declared" ]; then
          say "  ''${dim}none. sops-nix is imported on every nixarchy machine and does"
          say "  nothing at all until a secret is declared: no unit, no activation"
          say "  script, no package. That is the state this machine is in.''${off}"
        else
          while IFS= read -r n; do
            [ -n "$n" ] || continue
            printf '  %s%s%s  %s%s%s\n' "$bold" "$n" "$off" \
              "$dim" "$(printf '%s' "$json" | jq -r --arg n "$n" '.[$n].path // ""')" "$off"
            refs=$(printf '%s' "$json" | jq -r --arg n "$n" '.[$n].refs[]?')
            if [ -n "$refs" ]; then
              printf '%s\n' "$refs" | sed 's/^/      read by /'
            else
              printf '      %snothing in programs.nixarchy names it%s\n' "$dim" "$off"
            fi
          done <<< "$declared"
        fi
      fi

      step "Present in the encrypted stores"
      sysnames=$(names_in_store "$SYS_STORE")
      usernames=$(names_in_store "$USER_STORE")

      if [ -n "$sysnames" ]; then
        say "  ''${dim}$SYS_STORE''${off}"
        printf '%s\n' "$sysnames" | sed 's/^/    system  /'
      else
        say "  ''${dim}no system store at $SYS_STORE''${off}"
      fi
      if [ -n "$usernames" ]; then
        say "  ''${dim}$USER_STORE''${off}"
        printf '%s\n' "$usernames" | sed 's/^/    user    /'
      else
        say "  ''${dim}no user store at $USER_STORE''${off}"
      fi

      # The divergence is the finding. A name declared and not present fails
      # activation; a name present and not declared is dead weight nothing
      # reads. Neither is visible from either list on its own.
      if [ -n "$json" ] && [ -n "$declared" ]; then
        missing=$(comm -23 \
          <(printf '%s\n' "$declared" | sort) \
          <(printf '%s\n' "$sysnames" | sort))
        if [ -n "$missing" ]; then
          step "Declared, and not in the store"
          printf '%s\n' "$missing" | sed 's/^/    /'
          say  "  ''${dim}sops-nix fails activation for each of these.''${off}"
        fi
      fi

      say ""
      say "  ''${bold}nixarchy secret where <name>''${off}   what names one"
      say "  ''${bold}nixarchy secret copy''${off}           put one on the clipboard"
    }

    do_where() {
      local name=$1 json refs textual

      json=$(declared_json)

      step "$name"
      if [ -n "$json" ] && [ "$(printf '%s' "$json" | jq -r --arg n "$name" 'has($n)')" = true ]; then
        printf '  declared, at %s\n' "$(printf '%s' "$json" | jq -r --arg n "$name" '.[$n].path')"
        refs=$(printf '%s' "$json" | jq -r --arg n "$name" '.[$n].refs[]?')
        if [ -n "$refs" ]; then
          say "  ''${bold}Derived from the evaluated configuration:''${off}"
          printf '%s\n' "$refs" | sed 's/^/    /'
        else
          say "  ''${dim}nothing under programs.nixarchy names it, and no sops template"
          say "  renders it.''${off}"
        fi
      else
        warn "not declared in $FLAKE#nixosConfigurations.$HOST."
      fi

      # The grep is a SECOND answer, not the same one. The walk above covers
      # programs.nixarchy, the only surface with a convention we can rely on;
      # a reference in the user's own configuration --
      # `services.foo.passwordFile = config.sops.secrets.<name>.path` -- is
      # invisible to it and obvious to a grep. Labelled apart, because a
      # derived answer and a textual one are not the same claim.
      say ""
      say "  ''${bold}Named in the configuration text:''${off}"
      textual=$(grep -rn --include='*.nix' -F -- "$name" "$FLAKE" 2>/dev/null | head -20 || true)
      if [ -n "$textual" ]; then
        printf '%s\n' "$textual" | sed "s|$FLAKE/||" | sed 's/^/    /'
      else
        say "    ''${dim}nothing''${off}"
      fi
    }

    # ---- dispatch ------------------------------------------------------------
    #
    # tests/menu-verbs.nix reads the verbs out of this case block, in the
    # BUILT script, and checks every menu row that runs `nixarchy-secret
    # <verb>` against them. The `nixarchy-vm new` row that shipped broken --
    # a row written to match the menu key rather than the CLI -- is why.
    kind=system
    declare -a args=()
    for a in "$@"; do
      if [ "$a" = "--user" ]; then kind=user; else args+=("$a"); fi
    done
    set -- "''${args[@]:-}"

    case "''${1:-}" in
      new)
        [ -n "''${2:-}" ] || { fail "which secret? nixarchy secret new <name>"; exit 1; }
        do_new "$kind" "$2"
        ;;
      edit)
        do_edit "$kind"
        ;;
      remove)
        [ -n "''${2:-}" ] || { fail "which secret? nixarchy secret remove <name>"; exit 1; }
        do_remove "$kind" "$2"
        ;;
      list)
        do_list
        ;;
      where)
        [ -n "''${2:-}" ] || { fail "which secret? nixarchy secret where <name>"; exit 1; }
        do_where "$2"
        ;;
      copy)
        do_copy "''${2:-}"
        ;;
      "" | -h | --help | help)
        usage
        ;;
      *)
        fail "nixarchy secret: unknown subcommand '$1'"
        usage >&2
        exit 1
        ;;
    esac
  '';

  meta = {
    description = "Create, edit and read this machine's sops-nix secrets";
    mainProgram = "nixarchy-secret";
  };
}
