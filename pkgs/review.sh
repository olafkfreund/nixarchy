#!/usr/bin/env bash
# What needs updating, and what is quietly broken. Run it nightly, or now.
#
# The repo already watches Omarchy every night and merges the bump itself. What
# it did not have was anyone watching the watchers: on 2026-08-31 and 09-01 the
# Omarchy job was killed by its own timeout -- recorded as *cancelled*, which
# `if: failure()` does not catch -- and on 09-02 it failed on a false positive.
# Three nights, no issue, no notification, and a security release left on the
# shelf. Nothing was broken about the checks; nothing was listening.
#
# So this reports rather than acts. Two questions, one table:
#
#   is anything we pin behind what upstream ships?
#   did the jobs that are supposed to answer that actually run, and pass?
#
# It is a script rather than YAML for the reason doctor.sh and verify.sh are:
# something that only ever executes on a schedule is something nobody can test.
# `nix run .#review` gives the same answer at a prompt as it does at 06:00.
#
# Usage:
#   nix run .#review              print the table
#   nix run .#review -- --report  and sync the rolling issue
#   nix run .#review -- --list-pins   what we pin, no network (checks.review-pins)
#
# Exit status is 0 whether or not there are findings. Findings are the output,
# not an error -- the same rule verify.sh states in its own header. Only being
# unable to look is a failure.
set -uo pipefail

bold=$(printf '\033[1m')
dim=$(printf '\033[2m')
red=$(printf '\033[31m')
green=$(printf '\033[32m')
yellow=$(printf '\033[33m')
off=$(printf '\033[0m')

mode=table
case "${1-}" in
  --report) mode=report ;;
  --list-pins) mode=pins ;;
  "") ;;
  *)
    echo "usage: review [--report|--list-pins]" >&2
    exit 2
    ;;
esac

# Every hand-pinned package: name, the file that pins it, the GitHub repo to
# ask. Kept here rather than derived, because the point of the list is to be
# read -- a pin nobody remembers is exactly the one that goes stale.
#
# grok-bot is absent on purpose: it is pinned to a Cursor CDN commit hash with
# no queryable "latest", so there is nothing to compare it against. Its
# staleness is probed by date instead, below.
pins=$(
  cat <<'EOF'
once	pkgs/apps/once.nix	basecamp/once
hey-cli	pkgs/apps/hey-cli.nix	basecamp/hey-cli
omacalc	pkgs/apps/omacalc.nix	omacom/omacalc
omacut	pkgs/apps/omacut.nix	omacom/omacut
omawrite	pkgs/apps/omawrite.nix	omacom/omawrite
ttfx	pkgs/apps/ttfx.nix	omacom/ttfx
EOF
)

pinned_version() {
  # The first `version = "x"` in the file. Every pkgs/apps/*.nix states it
  # once, at the top; the updateScripts already read it exactly this way.
  sed -n 's/.*version = "\([^"]*\)".*/\1/p' "$1" | head -1
}

if [ "$mode" = pins ]; then
  # No network, no gh, no nix: just what the tree claims to pin. This is what
  # checks.review-pins asserts on, because the way this script rots is someone
  # restructuring a `version =` line and every probe below silently reporting
  # nothing at all.
  while IFS=$'\t' read -r name file _repo; do
    [ -n "$name" ] || continue
    printf '%s\t%s\t%s\n' "$name" "$file" "$(pinned_version "$file")"
  done <<<"$pins"
  exit 0
fi

findings=0
rows=""

row() { rows="$rows| $1 | $2 | $3 | $4 |"$'\n'; }
ok() { row "$1" "$2" "$3" "ok"; }
finding() {
  row "$1" "$2" "$3" "**$4**"
  findings=$((findings + 1))
}

# ---------------------------------------------------------------- upstream --

latest_tag() {
  # A release if the project cuts them, the newest tag if it does not.
  # omacom/omacalc publishes no releases at all and answers 404, which is a
  # fact about that repo rather than an error worth reporting.
  # On a 404 gh prints the error body to STDOUT and exits non-zero, so the
  # status is the only thing worth believing: taken on emptiness alone, this
  # reported omacalc's "latest version" as a JSON blob about Not Found.
  local repo=$1 tag=""
  tag=$(gh api "repos/$repo/releases/latest" --jq .tag_name 2>/dev/null) ||
    tag=$(gh api "repos/$repo/tags" \
      --jq 'map(.name) | map(select(test("^v?[0-9]"))) | .[0] // empty' 2>/dev/null) ||
    tag=""
  printf '%s' "$tag"
}

echo "${bold}Looking upstream${off}" >&2

omarchy_pin=$(grep -oE 'github:basecamp/omarchy/[^"]+' flake.nix | head -1 | cut -d/ -f3)
omarchy_latest=$(latest_tag basecamp/omarchy)
if [ -z "$omarchy_latest" ]; then
  finding "omarchy" "$omarchy_pin" "?" "cannot reach GitHub"
elif [ "$omarchy_pin" != "$omarchy_latest" ]; then
  finding "omarchy" "$omarchy_pin" "$omarchy_latest" "bump (omarchy.yml should do this nightly)"
else
  ok "omarchy" "$omarchy_pin" "$omarchy_latest"
fi

# Does the newest Omarchy's Install menu name a package no catalogue maps? The
# menu is in the source tree, so this answers "can we adopt it" without
# building anything -- and it is the question that blocked v4.0.2.
if [ -n "$omarchy_latest" ] && [ -x .github/scripts/check-menu-mapping.py ] ||
  [ -f .github/scripts/check-menu-mapping.py ]; then
  menu=$(mktemp)
  if curl -fsSL \
    "https://raw.githubusercontent.com/basecamp/omarchy/$omarchy_latest/default/omarchy/omarchy-menu.jsonc" \
    -o "$menu" 2>/dev/null; then
    if out=$(python3 .github/scripts/check-menu-mapping.py \
      "$menu" data/apps.nix data/services.nix 2>&1); then
      ok "menu rows ($omarchy_latest)" "${out#all }" "mapped"
    else
      finding "menu rows ($omarchy_latest)" "-" \
        "$(echo "$out" | grep -c '::error::') unmapped" \
        "map them in data/apps.nix"
    fi
  fi
  rm -f "$menu"
fi

while IFS=$'\t' read -r name file repo; do
  [ -n "$name" ] || continue
  have=$(pinned_version "$file")
  latest=$(latest_tag "$repo")
  latest=${latest#v}
  if [ -z "$latest" ]; then
    finding "$name" "$have" "?" "cannot reach GitHub"
  elif [ "$have" != "$latest" ]; then
    finding "$name" "$have" "$latest" "bump $file"
  else
    ok "$name" "$have" "$latest"
  fi
done <<<"$pins"

# grok-bot pins a CDN build by commit hash. Nothing upstream answers "is there
# a newer one", so the only honest signal is how long it has been since anyone
# looked.
age_days=$(( ($(date +%s) - $(git log -1 --format=%ct -- pkgs/apps/grok-bot.nix)) / 86400 ))
if [ "$age_days" -gt 60 ]; then
  finding "grok-bot" "$(pinned_version pkgs/apps/grok-bot.nix)" "unknowable" \
    "pinned by CDN commit, untouched for $age_days days -- check by hand"
else
  ok "grok-bot" "$(pinned_version pkgs/apps/grok-bot.nix)" "checked ${age_days}d ago"
fi

# ------------------------------------------------------------- consistency --

# The tag is written in three places. omarchy.yml rewrites all three now, but
# it did not always, and a mismatch means the store path names a version the
# tree is not.
nvim_version=$(sed -n 's/.*omarchyVersion ? "\([^"]*\)".*/\1/p' \
  pkgs/omarchy-nvim/default.nix | head -1)
pkg_version=$(sed -n 's/.*omarchyVersion = "\([^"]*\)".*/\1/p' flake.nix | head -1)
if [ "$pkg_version" = "${omarchy_pin#v}" ] && [ "$nvim_version" = "${omarchy_pin#v}" ]; then
  ok "version literals" "$pkg_version" "match the pin"
else
  finding "version literals" "flake $pkg_version / nvim $nvim_version" \
    "${omarchy_pin#v}" "one of the three copies is stale"
fi

# Is what main vendors actually released? The bump merges itself, so main can
# move to a new Omarchy without anyone noticing that the newest ISO on the
# releases page still carries the old one -- release.yml only fires on a tag,
# and nothing pushes tags. Publishing an image is the one step worth a person;
# forgetting it for a fortnight is not.
release=$(gh api "repos/{owner}/{repo}/releases" \
  --jq '.[0] | "\(.tag_name)\t\(.published_at)"' 2>/dev/null)
if [ -z "$release" ]; then
  finding "release" "${pkg_version:-?}" "?" "cannot reach GitHub"
else
  IFS=$'\t' read -r rel_tag rel_when <<<"$release"
  # v4.0.1-5 -> 4.0.1: the tag is the Omarchy version plus a packaging number,
  # and release.yml already asserts that half matches what the flake vendors.
  rel_omarchy=${rel_tag#v}
  rel_omarchy=${rel_omarchy%-*}
  rel_age=$((($(date +%s) - $(date -d "$rel_when" +%s)) / 86400))
  if [ "$rel_omarchy" = "$pkg_version" ]; then
    ok "release" "$rel_tag" "vendors $pkg_version, ${rel_age}d old"
  else
    finding "release" "$rel_tag (Omarchy $rel_omarchy)" "main vendors $pkg_version" \
      "no ISO for it -- tag v$pkg_version-1 to publish one"
  fi
fi

# The quickshell override carries a DELETE THIS. Nothing tested the condition,
# so it would have outlived its reason silently.
if grep -q 'quickshell = final.quickshell.overrideAttrs' flake.nix; then
  pinned=$(sed -n '/quickshell = final.quickshell.overrideAttrs/,/};/p' flake.nix |
    sed -n 's/.*version = "\([^"]*\)".*/\1/p' | head -1)
  upstream=$(nix eval --raw nixpkgs#quickshell.version 2>/dev/null)
  if [ -z "$upstream" ]; then
    ok "quickshell override" "$pinned" "nixpkgs version unread"
  elif [ "$(printf '%s\n%s\n' "$pinned" "$upstream" | sort -V | tail -1)" = "$upstream" ]; then
    finding "quickshell override" "$pinned" "$upstream" \
      "nixpkgs caught up -- delete the override, close #35"
  else
    ok "quickshell override" "$pinned" "nixpkgs has $upstream, still needed"
  fi
fi

# ------------------------------------------------------------------ inputs --

# The flake's own pins. Omarchy declares no versions -- its package lists are
# bare Arch names, whatever Arch shipped that day -- so there is nothing to
# match version-for-version. What matters is the other direction: Omarchy 4.x
# configures Hyprland through the Lua API that landed in 0.55, so this repo has
# to carry a Hyprland new enough to read the configs it vendors. That is a
# floor, and a floor nobody was watching.
#
# Three shapes of pin, three different questions:
#
#   rev   is there a release newer than the commit we sit on?
#   tag   is there a newer tag?
#   ref   has the branch we track actually moved lately?
#
# Age alone is not a finding. nixpkgs is eleven days old and healthy;
# nix-systems has not needed a commit in three years. A pin that stopped moving
# when it was supposed to keep moving is the thing worth saying.
echo "${bold}Reading the flake's pins${off}" >&2

inputs=$(python3 pkgs/flake-pins.py 2>/dev/null)

while IFS=$'\t' read -r name kind repo at modified; do
  [ -n "$name" ] || continue
  # omarchy has its own probe above, which also checks the menu. One pin
  # should not be able to produce two rows.
  [ "$name" = omarchy ] && continue
  age=$((($(date +%s) - modified) / 86400))
  case "$kind" in
    rev)
      # A commit is as reproducible as a tag, and sometimes ahead of every tag
      # -- hyprland is pinned past v0.56.2 because that tag does not build in
      # the sandbox. So ask whether the newest tag is ahead of US, rather than
      # whether we happen to be sitting on one.
      newest=$(latest_tag "$repo")
      if [ -z "$newest" ]; then
        # Not necessarily a problem: sops-nix has exactly one tag, called
        # `assets`, which is why flake.nix pins it by rev in the first place.
        # Tell those apart from a GitHub that is not answering.
        if gh api "repos/$repo/tags" --jq length >/dev/null 2>&1; then
          ok "$name" "${at:0:9} (${age}d)" "upstream publishes no version tags"
        else
          finding "$name" "${at:0:9} (${age}d)" "?" "cannot reach GitHub"
        fi
      else
        ahead=$(gh api "repos/$repo/compare/$newest...$at" --jq .ahead_by 2>/dev/null)
        if [ -z "$ahead" ]; then
          ok "$name" "${at:0:9} (${age}d)" "$newest, not comparable"
        elif [ "$ahead" -gt 0 ]; then
          ok "$name" "${at:0:9} (${age}d)" "$ahead commits past $newest"
        else
          finding "$name" "${at:0:9} (${age}d)" "$newest" \
            "upstream tagged a release this pin does not have"
        fi
      fi
      ;;
    tag)
      newest=$(latest_tag "$repo")
      if [ -z "$newest" ]; then
        ok "$name" "$at" "tag list unreadable"
      elif [ "$newest" = "$at" ]; then
        ok "$name" "$at" "newest"
      else
        finding "$name" "$at" "$newest" "newer tag available"
      fi
      ;;
    ref)
      # A branch that has not moved in four months is either a very quiet
      # project or a ref that no longer means what it says -- disko's `latest`
      # is the one to watch here.
      if [ "$at" != "(default)" ] && [ "$age" -gt 120 ]; then
        finding "$name" "$at, ${age}d" "-" \
          "a ref chosen on purpose that has not moved in $age days"
      else
        ok "$name" "$at" "${age}d old"
      fi
      ;;
  esac
done <<<"$inputs"

# ---------------------------------------------------------------- CI health --

echo "${bold}Asking what CI did${off}" >&2

# Every scheduled workflow, and how long it may go without a run before its
# silence is itself the finding. review.yml is not in this list: a job that
# reports on its own last run has nothing to say on the night it is the thing
# that broke.
ci() {
  local wf=$1 stale_hours=$2 line conclusion when age
  line=$(gh run list --workflow "$wf" --limit 1 \
    --json conclusion,createdAt --jq '.[0] | "\(.conclusion)\t\(.createdAt)"' \
    2>/dev/null)
  if [ -z "$line" ]; then
    finding "$wf" "-" "no runs at all" "is the workflow disabled?"
    return
  fi
  IFS=$'\t' read -r conclusion when <<<"$line"
  age=$((($(date +%s) - $(date -d "$when" +%s)) / 3600))
  case "$conclusion" in
    success) : ;;
    null | "")
      # Still going. Not a finding -- this job runs at 06:00 and nightly can
      # still be installing a desktop.
      ok "$wf" "${age}h ago" "still running"
      return
      ;;
    cancelled)
      # The one that went unreported for two nights. Almost always a timeout.
      finding "$wf" "${age}h ago" "cancelled" "timed out, most likely -- raise the budget or split the job"
      return
      ;;
    *)
      finding "$wf" "${age}h ago" "$conclusion" "read the run"
      return
      ;;
  esac
  if [ "$age" -gt "$stale_hours" ]; then
    finding "$wf" "${age}h ago" "last run passed" "but nothing has run for ${age}h"
  else
    ok "$wf" "${age}h ago" "$conclusion"
  fi
}

ci build.yml 192
ci nightly.yml 30
ci omarchy.yml 30
ci update.yml 200
ci release.yml 8760

# -------------------------------------------------------------------- print --

when=$(date -u +%F)
table="| what | have | upstream | |"$'\n'"|---|---|---|---|"$'\n'"$rows"

echo
if [ "$findings" -eq 0 ]; then
  echo "${green}${bold}All green${off} -- nothing pinned is behind and every job ran and passed."
else
  echo "${yellow}${bold}$findings thing(s) need attention${off}"
fi
echo
echo "$table" | sed "s/\*\*/${red}/;s/\*\*/${off}/"
echo "${dim}$when${off}"

[ "$mode" = report ] || exit 0

# ------------------------------------------------------------------- report --

# One issue, edited in place, closed when the table is clean. A check broken
# for a week should read as one problem, not seven -- the same reasoning
# nightly.yml's reporter states, and the same find-or-create shape.
title="Nightly review: what needs updating and fixing"
# The run that wrote this, when there is one. Run from a prompt there is not,
# and half a URL is worse than none.
if [ -n "${GITHUB_RUN_ID:-}" ]; then
  run="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
else
  run="(run by hand)"
fi

existing=$(gh issue list --state open --search "\"$title\" in:title" \
  --json number --jq '.[0].number // empty' 2>/dev/null)

if [ "$findings" -eq 0 ]; then
  if [ -n "$existing" ]; then
    gh issue close "$existing" --comment "All green as of $when. $run"
    echo "closed #$existing"
  else
    echo "nothing to report"
  fi
  exit 0
fi

body="Reviewed $when. $run

$table

Edited in place each night by \`review.yml\`, and closed automatically when
everything is green. Run it yourself with \`nix run .#review\`."

if [ -n "$existing" ]; then
  gh issue edit "$existing" --body "$body"
  echo "updated #$existing"
else
  gh issue create --title "$title" --label dependencies --body "$body"
fi
