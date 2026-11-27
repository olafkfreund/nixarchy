if [ -e $skills/omarchy-contribute/SKILL.md ]; then
  substituteInPlace $skills/omarchy-contribute/SKILL.md \
    --replace-fail '# Contributing to Omarchy' '# Contributing to Nixarchy or Omarchy' \
    --replace-fail 'Omarchy lives at https://github.com/omacom/omarchy. Route each request to the right place:' 'This machine runs Nixarchy, Omarchy packaged for NixOS, so two projects can own a report: Nixarchy (<https://github.com/olafkfreund/nixarchy>) for anything specific to NixOS — the store, a rebuild, `nixarchy-apply`, a hardcoded `/usr` path, a replaced `omarchy-*` command — and Omarchy (<https://github.com/omacom/omarchy>) for anything that would happen identically on Arch. When unsure, file against Nixarchy; the `nixarchy` skill'"'"'s `contributing.md` has the full rule. For Omarchy itself, route each request to the right place:' \
    --replace-fail '## Is It Even Omarchy'"'"'s Bug?' '## Is It Even the Distribution'"'"'s Bug?' \
    --replace-fail 'Be strict here. Omarchy is a configuration layer over Arch Linux, so a bug' 'Be strict here. Omarchy is a configuration layer and Nixarchy packages it for NixOS, so a bug' \
    --replace-fail 'Omarchy'"'"'s sphere of control is roughly:' 'The distribution'"'"'s sphere of control is roughly the list below. Nixarchy owns the NixOS half of each line -- how the thing is packaged, seeded and exposed on NixOS -- and Omarchy owns the behaviour itself:' \
    --replace-fail 'A bug in a program Omarchy merely installs is **not** an Omarchy bug unless Omarchy'"'"'s own packaging or configuration is implicated. If it is not Omarchy'"'"'s, say so and stop.' 'A bug in a program the distribution merely installs is **not** its bug unless Nixarchy'"'"'s or Omarchy'"'"'s own packaging or configuration is implicated. If it belongs to neither, say so and stop.' \
    --replace-fail '1. **It is a verified bug in Omarchy'"'"'s sphere**, established on evidence.' '1. **It is a verified bug in Nixarchy'"'"'s or Omarchy'"'"'s sphere**, established on evidence.' \
    --replace-fail 'The bug template asks for system details (CPU, GPU, Omarchy version), a description' 'The bug template asks for system details (CPU, GPU, Omarchy version, and here `nixos-version` and the locked inputs from `nix flake metadata`), a description' \
    --replace-fail 'gh search issues --repo omacom/omarchy "<program> <symptom>"' 'gh search issues --repo olafkfreund/nixarchy "<program> <symptom>"' \
    --replace-fail 'gh issue list --repo omacom/omarchy --state all --search "<distinctive words>"' 'gh issue list --repo olafkfreund/nixarchy --state all --search "<distinctive words>"' \
    --replace-fail 'gh issue view <number> --repo omacom/omarchy --comments' 'gh issue view <number> --repo olafkfreund/nixarchy --comments' \
    --replace-fail 'gh issue comment <number> --repo omacom/omarchy --body "..."' 'gh issue comment <number> --repo olafkfreund/nixarchy --body "..."' \
    --replace-fail 'gh issue create --repo omacom/omarchy --title "..." --body "..."' 'gh issue create --repo olafkfreund/nixarchy --title "..." --body "..."' \
    --replace-fail 'Never develop against `/usr/share/omarchy`. Clone a working copy instead:' 'Never develop against `$OMARCHY_PATH`: it is a read-only store path. A fix to how Nixarchy packages Omarchy goes to `gh repo fork olafkfreund/nixarchy --clone`; a fix to Omarchy itself goes upstream:' \
    --replace-fail 'anything else. Leaving it off searches both, which is what you want here.' 'anything else. Leaving it off searches both, which is what you want here.'$'\n\n'"$(cat $1)" \
    --replace-fail '## Submitting a PR' "$(cat $2)"$'\n\n## Submitting a PR'
else
  substituteInPlace $skills/diagnose-crash/reporting.md \
    --replace-fail '# Reporting a Crash Upstream to Omarchy' '# Reporting a Crash to Nixarchy or Omarchy' \
    --replace-fail 'Read this only after concluding that a crash is genuinely Omarchy'"'"'s to fix.' 'Read this only after concluding that a crash is genuinely the distribution'"'"'s to fix. Two projects can own it: Nixarchy (<https://github.com/olafkfreund/nixarchy>) for anything specific to NixOS — the store, a rebuild, `nixarchy-apply`, a hardcoded `/usr` path, a replaced `omarchy-*` command — and Omarchy (<https://github.com/basecamp/omarchy>) for anything that would happen identically on Arch. When unsure, file against Nixarchy; the `nixarchy` skill'"'"'s `contributing.md` has the full rule.' \
    --replace-fail 'Omarchy is a configuration layer over Arch Linux, so a crash' 'Omarchy is a configuration layer and Nixarchy packages it for NixOS, so a crash' \
    --replace-fail 'Include what happened, what was expected, steps to reproduce, system details from' 'Include what happened, what was expected, steps to reproduce, `nixos-version` and the locked inputs from `nix flake metadata`, system details from' \
    --replace-fail '## Is it even Omarchy'"'"'s bug?' '## Is it even the distribution'"'"'s bug?' \
    --replace-fail 'Omarchy'"'"'s sphere of control is roughly:' 'The distribution'"'"'s sphere of control is roughly the list below. Nixarchy owns the NixOS half of each line -- how the thing is packaged, seeded and exposed on NixOS -- and Omarchy owns the behaviour itself:' \
    --replace-fail 'A crash in a program Omarchy merely installs is **not** an Omarchy bug unless' 'A crash in a program the distribution merely installs is **not** its bug unless' \
    --replace-fail 'Omarchy'"'"'s own packaging or configuration is implicated.' 'Nixarchy'"'"'s or Omarchy'"'"'s own packaging or configuration is implicated.' \
    --replace-fail 'If it is not Omarchy'"'"'s, say so and stop. Suggesting the right upstream project is' 'If it belongs to neither, say so and stop. Suggesting the right upstream project is' \
    --replace-fail '1. **It is a verified bug in Omarchy'"'"'s sphere**, established on evidence. Issues' '1. **It is a verified bug in Nixarchy'"'"'s or Omarchy'"'"'s sphere**, established on evidence. Issues' \
    --replace-fail 'gh search issues --repo omacom/omarchy "<program> crash"' 'gh search issues --repo olafkfreund/nixarchy "<program> crash"' \
    --replace-fail 'gh issue list --repo omacom/omarchy --state all --search "<signal> <program>"' 'gh issue list --repo olafkfreund/nixarchy --state all --search "<signal> <program>"' \
    --replace-fail 'gh issue view <number> --repo omacom/omarchy --comments' 'gh issue view <number> --repo olafkfreund/nixarchy --comments' \
    --replace-fail 'gh issue comment <number> --repo omacom/omarchy --body "..."' 'gh issue comment <number> --repo olafkfreund/nixarchy --body "..."' \
    --replace-fail 'gh issue create --repo omacom/omarchy --title "..." --body "..."' 'gh issue create --repo olafkfreund/nixarchy --title "..." --body "..."'

  # The agent-room half of the same file (#271): a search beside the gh
  # search, and closing the loop after filing -- the two sections live in
  # their own .md files rather than inline, because a multi-line bash
  # argument inside this indented string changes its minimal indentation
  # and makes nixfmt re-flow the entire installPhase. $'\n\n' keeps each
  # replacement on one source line for the same reason.
  substituteInPlace $skills/diagnose-crash/reporting.md \
    --replace-fail 'anything else. Leaving it off searches both, which is what you want here.' 'anything else. Leaving it off searches both, which is what you want here.'$'\n\n'"$(cat $1)" \
    --replace-fail 'the path to drag into the web form.' 'the path to drag into the web form.'$'\n\n'"$(cat $2)"
fi
