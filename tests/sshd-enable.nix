{ inputs, pkgs }:
let
  testLib = import ./lib.nix { inherit inputs; };
  enable = testLib.vmPackage "nixarchy-service-enable";
  disable = testLib.vmPackage "nixarchy-service-disable";
  catalogueDiff = testLib.vmPackage "nixarchy-catalogue-diff";
  vm = inputs.self.nixosConfigurations.vm.config;
  template = vm.environment.etc."nixarchy/services-template.nix".source;
  menu = vm.environment.etc."nixarchy/omarchy-menu.jsonc".source;
  # Row 23 only: the vm turns sshd on itself, so it cannot show an ordinary machine's facts.
  referenceEnable = builtins.head (
    builtins.filter (
      p: (p.pname or p.name or "") == "nixarchy-service-enable"
    ) inputs.self.nixosConfigurations.reference.config.environment.systemPackages
  );
in
pkgs.runCommand "nixarchy-sshd-enable"
  {
    nativeBuildInputs = with pkgs; [
      coreutils
      gnugrep
      gnused
      python3
    ];
  }
  ''
    fails=0
    export HOME=$PWD/home
    export XDG_CONFIG_HOME=$PWD/config
    export NIXARCHY_TEMPLATES=$PWD/templates
    export PATH=${catalogueDiff}/bin:$PATH
    mkdir -p "$HOME" "$XDG_CONFIG_HOME/nixarchy" "$NIXARCHY_TEMPLATES"
    file=$XDG_CONFIG_HOME/nixarchy/services.nix
    facts=$PWD/facts.json
    export NIXARCHY_SSH_FACTS=$facts
    ${pkgs.openssh}/bin/ssh-keygen -q -t ed25519 -N "" -f "$PWD/testkey"
    good=$(cat "$PWD/testkey.pub")
    export GOOD_KEY="$good"
    old='    # services.openssh.enable = true;  #@ openssh  # Remote login. Opens port 22 and NixOS defaults to keys only, not passwords.'
    enable=${enable}/bin/nixarchy-service-enable
    disable=${disable}/bin/nixarchy-service-disable
    omarchy-i18n() { echo "$1"; }
    omarchy-notification-send() { :; }
    export -f omarchy-i18n omarchy-notification-send

    field() {
      python3 -c 'import json,re,sys; raw=open(sys.argv[1]).read(); raw=re.sub(r"^\s*//[^\n]*(\n|$)", "", raw, flags=re.M); raw=re.sub(r",(\s*[}\]])", r"\1", raw); rows=json.loads(raw); print(rows[sys.argv[2]].get(sys.argv[3], "") if sys.argv[2] in rows else "__absent__")' "$@"
    }
    reset_case() {
      umask 022
      rm -rf "$HOME/.ssh"
      # install, not cp: a store file is read-only, and cp could not overwrite its own copy.
      install -m644 ${template} "$file"
      install -m644 ${template} "$NIXARCHY_TEMPLATES/services-template.nix"
      printf '%s\n' '{"declaredUsers":[],"homeRead":true,"otherSources":[],"sshdOn":false}' > "$facts"
      unset -f gum curl 2>/dev/null || true
      rc=0
      : > result
    }
    old_file() { printf '%s\n' '{ ... }:' '{' "$old" '}' > "$file"; }
    home_key() { mkdir -p "$HOME/.ssh"; printf '%s\n' "$1" > "$HOME/.ssh/authorized_keys"; }
    run_enable() { rc=0; "$enable" openssh </dev/null >result 2>&1 || rc=$?; }
    enabled() {
      [ "$rc" -eq 0 ] &&
        grep -qE '^[[:space:]]*programs[.]nixarchy[.]services[.]openssh[.]enable = true;.*#@ openssh' "$file"
    }
    refused() { [ "$rc" -eq 1 ] && grep -qF "$1" result; }
    unchanged() { [ "$(sha256sum < "$file")" = "$before" ]; }
    run_case() {
      if "$2"; then echo "case $1: ok";
      else echo "case $1: FAIL (exit $rc)" >&2; sed 's/^/  /' result >&2; fails=$((fails + 1)); fi
    }

    case1() {
      reset_case; old_file; home_key "$good"; run_enable
      enabled &&
        [ "$(grep -m1 '#@ openssh' "$file")" = "$(grep -m1 '#@ openssh' ${template} | sed -E 's/^([[:space:]]*)# ?/\1/')" ] &&
        ! grep -qF 'defaults to keys only' "$file"
    }
    case2() {
      reset_case; old_file; sed -i 's/^    # /    /' "$file"
      before=$(sha256sum < "$file"); run_enable
      [ "$rc" -eq 0 ] && unchanged && grep -qF 'passwords are still on' result
    }
    case3() {
      reset_case; before=$(sha256sum < "$file"); run_enable
      refused 'no key added' && unchanged
    }
    case4() {
      reset_case; sed -i '/#@ openssh/d' "$file"
      before=$(sha256sum < "$file"); run_enable
      refused 'no key added' && unchanged && ! grep -qF '#@ openssh' "$file"
    }
    case5() {
      reset_case; home_key '# no keys here'
      before=$(sha256sum < "$file"); run_enable
      refused 'no key added' && unchanged
    }
    case6() {
      reset_case; home_key "from=\"127.0.0.1\" $good"; run_enable; enabled
    }
    case7() {
      reset_case
      printf '{"declaredUsers":["%s"],"homeRead":true,"otherSources":[],"sshdOn":false}\n' "$(id -un)" > "$facts"
      run_enable; enabled && [ ! -e "$HOME/.ssh" ]
    }
    case8() {
      reset_case; home_key "$good"
      printf '%s\n' '{"declaredUsers":[],"homeRead":false,"otherSources":[],"sshdOn":false}' > "$facts"
      before=$(sha256sum < "$file"); key_before=$(sha256sum < "$HOME/.ssh/authorized_keys")
      gum() { if [ "$1" = choose ]; then echo sshd.keyPaste; else echo "$GOOD_KEY"; fi; }
      export -f gum
      run_enable
      refused 'sshd does not read' && unchanged &&
        [ "$(sha256sum < "$HOME/.ssh/authorized_keys")" = "$key_before" ]
    }
    case9() {
      reset_case
      printf '%s\n' '{"declaredUsers":[],"homeRead":false,"otherSources":["/keys"],"sshdOn":false}' > "$facts"
      gum() { [ "$1" = confirm ]; }
      export -f gum
      run_enable; enabled
    }
    case10() {
      reset_case
      printf '%s\n' '{"declaredUsers":[],"homeRead":true,"otherSources":["/keys"],"sshdOn":false}' > "$facts"
      gum() { return 1; }
      export -f gum
      before=$(sha256sum < "$file"); run_enable
      refused 'no key confirmed in /keys' && unchanged
    }
    case11() {
      reset_case; home_key "$good"
      printf '%s\n' '{"declaredUsers":[],"homeRead":true,"otherSources":[],"sshdOn":true}' > "$facts"
      before=$(sha256sum < "$file"); run_enable
      refused 'if you just turned the row off' && unchanged &&
        grep -qF 'PasswordAuthentication = false;' result &&
        grep -qF 'KbdInteractiveAuthentication = false;' result
    }
    case12() {
      reset_case
      gum() { if [ "$1" = choose ]; then echo sshd.keyPaste; else echo "$GOOD_KEY"; fi; }
      export -f gum
      run_enable
      enabled && [ "$(stat -c %a "$HOME/.ssh")" = 700 ] &&
        [ "$(stat -c %a "$HOME/.ssh/authorized_keys")" = 600 ] &&
        grep -qxF "$good" "$HOME/.ssh/authorized_keys"
    }
    case13() {
      reset_case
      gum() { if [ "$1" = choose ]; then echo sshd.keyFromGithub; else echo alice; fi; }
      curl() { printf '%s\n' "$GOOD_KEY" "$GOOD_KEY"; }
      export -f gum curl
      run_enable
      enabled && [ "$(grep -cxF "$good" "$HOME/.ssh/authorized_keys")" = 1 ]
    }
    case14() {
      reset_case
      gum() { if [ "$1" = choose ]; then echo sshd.keyPaste; else echo garbage; fi; }
      export -f gum
      before=$(sha256sum < "$file"); run_enable
      refused 'no key added' && unchanged && [ ! -e "$HOME/.ssh" ]
    }
    case15() {
      reset_case
      gum() { if [ "$1" = choose ]; then echo sshd.keyFromGithub; else echo alice; fi; }
      curl() { printf '%s\n' "$GOOD_KEY" 'garbage'; }
      export -f gum curl
      run_enable
      enabled && [ "$(wc -l < "$HOME/.ssh/authorized_keys")" = 1 ] &&
        grep -qxF "$good" "$HOME/.ssh/authorized_keys"
    }
    case16() {
      reset_case
      gum() { if [ "$1" = choose ]; then echo sshd.keyFromGithub; else echo alice; fi; }
      curl() { return 22; }
      export -f gum curl
      before=$(sha256sum < "$file"); run_enable
      refused "could not fetch keys for 'alice'" && unchanged
    }
    case17() {
      reset_case
      gum() { if [ "$1" = choose ]; then echo sshd.keyFromGithub; else echo ../x; fi; }
      curl() { touch "$HOME/curl-called"; }
      export -f gum curl
      run_enable
      refused 'is not a GitHub username' && [ ! -e "$HOME/curl-called" ]
    }
    case18() {
      reset_case; home_key "$good"
      before=$(sha256sum < "$file"); run_enable
      enabled && "$disable" openssh >/dev/null && unchanged
    }
    case19() {
      reset_case; old_file; home_key "$good"
      sed -i '/#@ openssh/d' "$NIXARCHY_TEMPLATES/services-template.nix"
      run_enable
      refused 'no openssh row' && ! grep -qE '^[[:space:]]*services[.]openssh[.]enable.*#@ openssh' "$file"
    }
    case20() {
      reset_case
      action="omarchy-launch-floating-terminal-with-presentation 'nixarchy-service-enable openssh'"
      [ "$(field ${menu} setup.security.sshd action)" = "$action" ] &&
        [ "$(field ${menu} install.service.openssh action)" = "$action" ] &&
        [ "$(field ${menu} remove.security.sshd action)" = 'nixarchy-service-disable openssh' ]
    }
    case21() {
      reset_case
      ! grep -qF 'defaults to keys only' ${template} &&
        grep -qE '^[[:space:]]*#[[:space:]]*programs[.]nixarchy[.]services[.]openssh[.]enable.*#@ openssh' ${template}
    }
    case22() {
      reset_case; old_file; home_key "$good"; run_enable
      enabled && "$disable" openssh >/dev/null &&
        [ "$(grep -m1 '#@ openssh' "$file")" = "$(grep -m1 '#@ openssh' ${template})" ]
    }
    case23() {
      reset_case
      baked=$(grep -oE '/nix/store/[^" ]+-nixarchy-ssh-facts[.]json' ${referenceEnable}/bin/nixarchy-service-enable | head -1)
      [ -n "$baked" ] && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["homeRead"] is True and d["sshdOn"] is False and d["otherSources"] == []' "$baked"
    }

    # An existing last line with no newline must not swallow the key (Codex, #1631).
    case24() {
      reset_case
      mkdir -p "$HOME/.ssh"
      printf '# no keys' > "$HOME/.ssh/authorized_keys"
      gum() { if [ "$1" = choose ]; then echo sshd.keyPaste; else echo "$GOOD_KEY"; fi; }
      export -f gum
      run_enable
      enabled && grep -qxF "$good" "$HOME/.ssh/authorized_keys" &&
        grep -qxF '# no keys' "$HOME/.ssh/authorized_keys"
    }

    for n in $(seq 1 24); do run_case "$n" "case$n"; done
    [ "$fails" -eq 0 ]
    echo 'sshd-enable: every case passed'
    touch $out
  ''
