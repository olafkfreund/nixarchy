{ pkgs, installScript }:
# clone_repo and finish_clone, driven against git repositories built here.
#
# --from-repo is the mode that touches a USER'S CONFIG REPOSITORY, and until
# this file neither of its branches -- host already in the repo, host added to
# the repo -- had ever executed under any test (`grep -rn from_repo tests/`
# matched nothing). The same doctrine as tests/installer-store-space.nix: the
# functions on their own, extracted rather than sourced (sourcing install.sh
# runs a wizard), their dependencies stubbed, and every assertion made against
# what the code DID -- files written, files left alone, a tree staged -- never
# against what install.sh's text contains. Text-presence is how the encrypted
# branch shipped unreachable.
#
# No network: the repositories are `git init`ed in the build and cloned over
# file://, which exercises the same `git clone --depth 1` line the real mode
# runs against a remote.
#
# No VM, deliberately. The disk half of --from-repo is not a separate path:
# once finish_clone returns, main() proceeds through the same format_disk /
# install_flake_dir sequence checks.install already proves against a real
# qcow2. What is unique to this mode is which flake those steps consume and
# what happens to the repository on the way -- and that is all decided in the
# two functions this file drives.
pkgs.runCommand "nixarchy-installer-from-repo"
  {
    nativeBuildInputs = [ pkgs.git ];
  }
  ''
    # The functions on their own. Both, because they are two halves of one
    # decision: clone_repo decides whether the host exists, finish_clone acts
    # on that answer after the questions (if any) have run.
    sed -n '/^clone_repo()/,/^}/p' ${installScript} > fr.sh
    test -s fr.sh || { echo "clone_repo is not in install.sh any more" >&2; exit 1; }
    sed -n '/^finish_clone()/,/^}/p' ${installScript} >> fr.sh
    grep -q '^finish_clone()' fr.sh || { echo "finish_clone is not in install.sh any more" >&2; exit 1; }

    export HOME=$PWD
    git config --global user.email test@test
    git config --global user.name test
    git config --global init.defaultBranch main

    # What $TEMPLATE provides: a host skeleton whose content is recognisably
    # the template's, so "copied from the template" and "left as the
    # repository wrote it" are distinguishable by reading one line.
    mkdir -p template/host
    echo 'TEMPLATE-DEFAULT' > template/host/default.nix
    echo 'TEMPLATE-HW' > template/host/hardware-configuration.nix

    # The fleet repository: one machine its administrator wrote (alpha, with
    # its own hardware-configuration.nix -- the one file finish_clone must
    # NOT keep), plus content that is neither host -- which the "adding"
    # branch promises comes along untouched.
    mkdir -p repo/hosts/alpha
    echo 'ALPHA-OWNED' > repo/hosts/alpha/default.nix
    echo 'ALPHA-HW' > repo/hosts/alpha/hardware-configuration.nix
    echo 'fleet-theme' > repo/themes.nix
    git -C repo init -q
    git -C repo add -A
    git -C repo commit -qm fixture

    # A configuration from before the hosts/ layout: a git repository, but
    # its files at the top level. clone_repo's second refusal.
    mkdir -p nohosts
    echo 'old-layout' > nohosts/flake.nix
    git -C nohosts init -q
    git -C nohosts add -A
    git -C nohosts commit -qm fixture

    fails=0
    failed() { echo "  FAILED  $1"; fails=$((fails + 1)); }

    # ---- branch 1: the repository already describes the machine ----------
    # Everything except hardware is the repository's word, kept verbatim.
    (
      set -e
      . ./fr.sh
      TEMPLATE=$HOME/template
      from_repo="file://$HOME/repo"
      from_host=alpha
      substitute_host_files() { touch "$HOME/subst-called-alpha"; }
      clone_repo   > "$HOME/out-alpha" 2>&1
      finish_clone >> "$HOME/out-alpha" 2>&1
      echo "$from_host_exists" > "$HOME/exists-alpha"
      echo "$work" > "$HOME/work-alpha"
    ) || failed "the existing-host path did not run to completion"

    wa=$(cat work-alpha 2>/dev/null || true)
    [ "$(cat exists-alpha 2>/dev/null)" = true ] \
      || failed "hosts/alpha is in the repository but from_host_exists is not true"
    grep -q 'describes alpha; using it' out-alpha \
      || failed "the existing-host branch did not say it was using the repository's alpha"
    # The administrator's files, byte for byte -- an installer that "helpfully"
    # re-templated an existing host would destroy the very thing this mode is
    # for.
    [ "$(cat "$wa/hosts/alpha/default.nix")" = ALPHA-OWNED ] \
      || failed "the repository's own hosts/alpha/default.nix was rewritten"
    [ ! -e subst-called-alpha ] \
      || failed "substitute_host_files ran on a host the repository already wrote"
    # Except hardware, which is the one thing a configuration written
    # somewhere else cannot know: always regenerated, never taken.
    if grep -q ALPHA-HW "$wa/hosts/alpha/hardware-configuration.nix"; then
      failed "the repository's hardware-configuration.nix was kept -- another machine's hardware"
    fi
    grep -q '{ }' "$wa/hosts/alpha/hardware-configuration.nix" \
      || failed "hardware-configuration.nix was not regenerated as the placeholder"
    # Left STAGED, and only staged: no commit of ours, and the origin
    # untouched -- the installer has no git identity and must not invent one.
    git -C "$wa" diff --cached --name-only | grep -q 'hosts/alpha/hardware-configuration.nix' \
      || failed "the regenerated hardware-configuration.nix is not staged"
    [ "$(git -C "$wa" rev-list --count HEAD)" = 1 ] \
      || failed "finish_clone committed; the tree is supposed to be left staged"
    [ "$(git -C repo rev-list --count HEAD)" = 1 ] \
      || failed "the ORIGIN repository gained a commit; nothing may be pushed back"

    # ---- branch 2: a machine the repository has never seen ----------------
    # The template host is copied in beside the existing machines; everything
    # already there comes along untouched.
    (
      set -e
      . ./fr.sh
      TEMPLATE=$HOME/template
      from_repo="file://$HOME/repo"
      from_host=beta
      substitute_host_files() { touch "$HOME/subst-called-beta"; }
      clone_repo   > "$HOME/out-beta" 2>&1
      finish_clone >> "$HOME/out-beta" 2>&1
      echo "$from_host_exists" > "$HOME/exists-beta"
      echo "$work" > "$HOME/work-beta"
    ) || failed "the new-host path did not run to completion"

    wb=$(cat work-beta 2>/dev/null || true)
    [ "$(cat exists-beta 2>/dev/null)" = false ] \
      || failed "hosts/beta is not in the repository but from_host_exists is not false"
    grep -q 'has no beta; adding it' out-beta \
      || failed "the new-host branch did not say it was adding beta"
    [ "$(cat "$wb/hosts/beta/default.nix")" = TEMPLATE-DEFAULT ] \
      || failed "hosts/beta was not copied from the template"
    [ -e subst-called-beta ] \
      || failed "substitute_host_files never ran on the new host -- the answers would not reach it"
    grep -q '{ }' "$wb/hosts/beta/hardware-configuration.nix" \
      || failed "the new host's hardware-configuration.nix was not regenerated as the placeholder"
    # "Comes along untouched": the other machine and the top-level content.
    [ "$(cat "$wb/hosts/alpha/default.nix")" = ALPHA-OWNED ] \
      || failed "adding beta disturbed the repository's existing alpha"
    [ "$(cat "$wb/themes.nix")" = fleet-theme ] \
      || failed "adding beta lost the repository's own top-level content"
    git -C "$wb" diff --cached --name-only | grep -q 'hosts/beta/default.nix' \
      || failed "the new host is not staged"
    [ "$(git -C repo rev-list --count HEAD)" = 1 ] \
      || failed "the ORIGIN repository gained a commit on the new-host path"

    # ---- the refusals ------------------------------------------------------
    # Each in its own subshell because clone_repo exits, not returns.
    if ( . ./fr.sh
         from_repo="file://$HOME/no-such-repo"
         from_host=alpha
         clone_repo > "$HOME/out-noclone" 2>&1 ); then
      failed "a repository that cannot be cloned was not refused"
    else
      grep -q 'could not clone' out-noclone \
        || failed "the clone refusal does not say the clone failed"
    fi

    if ( . ./fr.sh
         from_repo="file://$HOME/nohosts"
         from_host=alpha
         clone_repo > "$HOME/out-nohosts" 2>&1 ); then
      failed "a repository with no hosts/ directory was not refused"
    else
      grep -q 'has no hosts/ directory' out-nohosts \
        || failed "the no-hosts refusal does not name the missing layout"
    fi

    # ---- and main() actually runs them -------------------------------------
    # The same doctrine as installer-store-space's last stanza: everything
    # above stays green with the call sites deleted, which would be #133 again
    # -- written, extracted, asserted, and run by nothing. Line order, because
    # clone_repo must have decided from_host_exists BEFORE the questions run,
    # and finish_clone must have written the tree BEFORE anything consumes it.
    # `|| true` because stdenv sets pipefail and a grep with no match must
    # reach the named refusal rather than kill the script mid-pipe.
    clone_line=$(grep -n '^    clone_repo$' ${installScript} | cut -d: -f1 | head -1 || true)
    finish_line=$(grep -n '^    finish_clone$' ${installScript} | cut -d: -f1 | head -1 || true)
    fmt_line=$(grep -n '^    format_disk &&' ${installScript} | cut -d: -f1 | head -1 || true)
    [ -n "$clone_line" ] || { echo "main() no longer calls clone_repo" >&2; exit 1; }
    [ -n "$finish_line" ] || { echo "main() no longer calls finish_clone" >&2; exit 1; }
    [ -n "$fmt_line" ] && [ "$clone_line" -lt "$finish_line" ] && [ "$finish_line" -lt "$fmt_line" ] || {
      echo "main() does not run clone_repo, then finish_clone, then format_disk" >&2
      exit 1
    }

    [ "$fails" = 0 ] || exit "$fails"
    echo "clone_repo takes both branches, refuses both bad repositories, and pushes nothing back"
    touch $out
  ''
