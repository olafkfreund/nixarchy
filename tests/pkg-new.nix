{ pkgs }:
# `nixarchy pkg new` against stub nix-init and nix, offline.
#
# What only this check can reach: the command's promises that need a network
# to exercise for real. The draft is KEPT when the build fails (#581's
# decision 2 -- a failed draft beats a blank file); the placeholder hash
# nix-init leaves for cargo/vendor deps is filled in from the failed build's
# own "got:" line; the apps.nix line is inserted COMMENTED OUT, and only
# inside the #@pkgs-end block nixarchy-pkg-add wrote -- a reshaped file gets
# instructions, not an edit. checks.options covers the dispatcher route and
# the refusals that need no stubs; nothing automated covers a real nix-init
# run, which needs the network (see tests/AGENTS.md).
#
# Stubs shadow the real commands because this runs the RAW pkgs/pkg-new.sh,
# not the writeShellApplication -- the installed command's PATH is strict and
# cannot be stubbed, which is exactly why the body lives in its own file.
pkgs.runCommand "nixarchy-pkg-new"
  {
    nativeBuildInputs = [
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
      pkgs.coreutils
    ];
  }
  ''
    export HOME=$PWD/home
    export XDG_CONFIG_HOME=$HOME/.config
    mkdir -p "$HOME" stub

    sed 's|@nixpkgs@|/stub-nixpkgs|' ${../pkgs/pkg-new.sh} > pkg-new.sh

    # A draft the way headless nix-init leaves one for Rust: the src hash
    # prefetched, the cargoHash a placeholder only a build can name.
    cat > stub/nix-init <<'EOF'
    #!/bin/sh
    for last; do :; done
    if [ "''${STUB_INIT_FAIL:-}" = 1 ]; then echo "error: no clue" >&2; : > "$last"; exit 1; fi
    printf '{ rustPlatform }:\nrustPlatform.buildRustPackage {\n  pname = "tool";\n  cargoHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";\n}\n' > "$last"
    EOF

    # A build that fails with a hash mismatch until the draft carries the
    # real hash, then succeeds -- fetchCargoVendor's actual behaviour, minus
    # the network. STUB_NIX_FAIL=1 is a build that is simply broken.
    cat > stub/nix <<'EOF'
    #!/bin/sh
    draft=$(ls "$XDG_CONFIG_HOME"/nixarchy/packages/*.nix)
    if [ "''${STUB_NIX_FAIL:-}" = 1 ]; then echo "error: builder failed with exit code 1" >&2; exit 1; fi
    if grep -q 'sha256-GOTGOTGOTGOTGOTGOTGOTGOTGOTGOTGOTGOTGOTGOT=' "$draft"; then exit 0; fi
    echo "error: hash mismatch in fixed-output derivation:" >&2
    echo "         specified: sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" >&2
    echo "            got:    sha256-GOTGOTGOTGOTGOTGOTGOTGOTGOTGOTGOTGOTGOTGOT=" >&2
    exit 1
    EOF
    chmod +x stub/nix-init stub/nix
    export PATH=$PWD/stub:$PATH

    fails=0
    fail() { echo "  FAILED  $1"; fails=$((fails + 1)); }
    ok() { echo "  ok      $1"; }
    cfg=$XDG_CONFIG_HOME/nixarchy
    draft=$cfg/packages/tool.nix

    # The block nixarchy-pkg-add writes, in the shape it writes it.
    mkapps() {
      mkdir -p "$cfg"
      cat > "$cfg/apps.nix" <<'EOF'
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [  #@pkgs-begin
      ];  #@pkgs-end
    }
    EOF
    }

    # -- refusals, before anything is touched ------------------------------
    if o=$(bash pkg-new.sh not-a-url 2>&1); then fail "a non-URL was accepted"
    elif printf '%s' "$o" | grep -q "does not look like a URL"; then ok "a non-URL is refused, naming pkg add"
    else fail "the non-URL refusal does not say why"; fi

    if o=$(bash pkg-new.sh 2>&1); then fail "no argument was accepted"
    else ok "no argument prints usage and fails"; fi

    # -- nix-init failing leaves nothing behind ----------------------------
    mkapps
    if o=$(STUB_INIT_FAIL=1 bash pkg-new.sh https://example.org/x/tool 2>&1); then
      fail "a failed nix-init reported success"
    elif [ -e "$draft" ]; then fail "a failed nix-init left an empty draft, which blocks the next run"
    else ok "a failed nix-init leaves no draft behind"; fi

    # -- the happy path: placeholder hash filled in from the failed build --
    if ! o=$(bash pkg-new.sh https://example.org/x/tool 2>&1); then
      printf '%s\n' "$o" | sed 's/^/          | /'
      fail "the draft-builds path did not succeed"
    else
      grep -q 'sha256-GOTGOTGOTGOTGOTGOTGOTGOTGOTGOTGOTGOTGOTGOT=' "$draft" \
        && ok "the placeholder hash was filled in from the failed build" \
        || fail "the placeholder hash is still in the draft"
      printf '%s' "$o" | grep -q "DRAFT" \
        && ok "the result is presented as a draft, not a package" \
        || fail "nothing in the output says DRAFT"
      grep -q '^    # (callPackage ./packages/tool.nix { })  #@draft tool$' "$cfg/apps.nix" \
        && ok "apps.nix gained the line, commented out" \
        || fail "apps.nix did not gain the commented line"
      # Inserted INSIDE the block: before the end marker, after the begin.
      awk '/#@pkgs-begin/{b=NR} /#@draft tool/{d=NR} /#@pkgs-end/{e=NR} END{exit !(b<d && d<e)}' "$cfg/apps.nix" \
        && ok "the line sits inside the #@pkgs block" \
        || fail "the line is outside the #@pkgs block"
    fi

    if o=$(bash pkg-new.sh https://example.org/x/tool 2>&1); then
      fail "an existing draft was overwritten"
    else
      ok "an existing draft refuses a redraft"
      printf '%s' "$o" | grep -q -- '--update' \
        && ok "the refusal names --update as the deliberate way" \
        || fail "the refusal does not say how to redraft on purpose"
    fi

    # -- --update redrafts over the existing draft -------------------------
    echo '# my edits' >> "$draft"
    lines_before=$(grep -c '#@draft tool$' "$cfg/apps.nix")
    if ! o=$(bash pkg-new.sh --update https://example.org/x/tool 2>&1); then
      printf '%s\n' "$o" | sed 's/^/          | /'
      fail "--update did not redraft over an existing draft"
    else
      grep -q '# my edits' "$draft" \
        && fail "--update kept the old draft instead of redrafting" \
        || ok "--update replaced the draft with a fresh one"
      [ "$lines_before" = "$(grep -c '#@draft tool$' "$cfg/apps.nix")" ] \
        && ok "--update did not duplicate the apps.nix line" \
        || fail "--update wrote a second #@draft line into apps.nix"
    fi

    # -- --update, but nix-init fails: the edited draft comes back ---------
    echo '# my edits' >> "$draft"
    if o=$(STUB_INIT_FAIL=1 bash pkg-new.sh --update https://example.org/x/tool 2>&1); then
      fail "--update reported success though nix-init failed"
    elif grep -q '# my edits' "$draft"; then
      ok "a failed --update gives the edited draft back"
    else
      fail "a failed --update traded the edited draft for nothing"
    fi

    # -- the build fails: reported as a failure, draft KEPT ----------------
    rm -rf "$cfg"; mkapps
    if o=$(STUB_NIX_FAIL=1 bash pkg-new.sh https://example.org/x/tool 2>&1); then
      fail "a draft that does not build was reported as success"
    else
      [ -f "$draft" ] \
        && ok "the failed draft is kept for editing" \
        || fail "the failed draft was discarded"
      printf '%s' "$o" | grep -q "did NOT build" \
        && ok "the failure is named out loud" \
        || fail "the failure report does not say the draft did not build"
      grep -q '#@draft' "$cfg/apps.nix" \
        && fail "a draft that does not build was still added to apps.nix" \
        || ok "apps.nix is untouched by a failed draft"
    fi

    # -- a reshaped apps.nix is not edited ---------------------------------
    rm -rf "$cfg"; mkdir -p "$cfg"
    echo '{ ... }: { }' > "$cfg/apps.nix"
    before=$(cksum < "$cfg/apps.nix")
    if o=$(bash pkg-new.sh https://example.org/x/tool 2>&1); then
      [ "$before" = "$(cksum < "$cfg/apps.nix")" ] \
        && ok "a file without the marker is left alone" \
        || fail "a file without nixarchy-pkg-add's marker was edited"
      printf '%s' "$o" | grep -q "add it to your configuration yourself" \
        && ok "the edit is printed instead" \
        || fail "nothing told the user what to add by hand"
    else fail "a marker-less apps.nix broke the drafting"; fi

    [ "$fails" -eq 0 ] || { echo; echo "$fails assertion(s) failed"; exit 1; }
    touch $out
  ''
