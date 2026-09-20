# Ask Codex Input

## Question

Second opinion on two small PRs that together address nixarchy issue #741. Repos: /mnt/data/Source-home/nixarchy (branch docs/741-claude-outside-nix, PR #753) and /mnt/data/Source-home/GitHub/nixi-nixarchy (branch fix/adapter-message-names-nixarchy-route, PR #17).

THE PROBLEM (#741): nixarchy pins Claude's ACP adapter (claude-agent-acp) only when 'programs.nixarchy.apps.claude-code.enable' is true OR 'programs.nixarchy.defaultAgent == "claude"' (modules/home.nix:615-619). A real machine used Claude installed via mise into ~/.local/bin, with neither condition true. The only record of the choice is ~/.config/omarchy/defaults/agent, runtime state no Nix module can read. Result: no adapter pinned, and SUPER+H fails with a PATH error while the rebuild says nothing.

WHAT I DID:
1. nixarchy PR #753: documentation only, a new section in docs/manual/ai.md. It gives a table of which adapters are pinned when, tells the user to write 'services.nixi.agents = [ "claude" ]', and warns that (a) it MERGES with nixarchy's list rather than replacing it, and (b) it pulls in nixpkgs' claude-code because claude-agent-acp sets CLAUDE_CODE_EXECUTABLE to it, so a mise user ends up with two Claudes.
2. nixi PR #17: the existing runtime error already named 'pkgs.claude-agent-acp'. I changed it to name the nixarchy route first ('services.nixi.agents = [ "claude" ]'), keep pkgs.<name> for plain NixOS, and add that the change only reaches a running shell after omarchy-restart-shell. I also tightened the test, which previously matched the new message too and so would not have noticed the new clause being deleted.

WHAT I DELIBERATELY DID NOT DO: an activation-time warning (option 2 in the issue), on the grounds that the runtime message already names the fix and reaches the user exactly when they hit the problem, and a second diagnostic has to earn its maintenance. I also did NOT add a new 'programs.nixarchy.agents' option (option 1 in the issue) because services.nixi.agents already exists and works, and because option 1's stated promise -- an opt-in independent of how the CLI was installed -- is false given CLAUDE_CODE_EXECUTABLE.

VERIFIED: the merge behaviour by evaluation ({"without":["opencode","codex"],"withClaude":["claude","opencode","codex"]}); the nixi test fails when the new clause is removed (6 pass, 1 fail) and passes restored (41/41 across bridge/*.test.js).

QUESTIONS: (1) Is documentation-plus-runtime-message the right resolution for #741, or am I under-solving a real trap by refusing the activation warning? (2) Is my claim about CLAUDE_CODE_EXECUTABLE actually correct for the version pinned here, and does 'services.nixi.agents = [ "claude" ]' really leave a mise-installed claude unused? (3) Is there a cheap declarative signal I have missed that WOULD let a Nix module detect a non-Nix Claude? (4) Anything wrong or misleading in the doc text itself? (5) Should #741 close on these two PRs, or does something remain?

## Configuration

- Model: gpt-5.5
- Effort: high
- Timeout: 3600s
- Timestamp: 2026-09-18_08-15-36
- Tool: codex
