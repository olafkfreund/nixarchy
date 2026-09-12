# pkgs/

The Omarchy tree as a derivation, the commands this repository writes itself,
and the packages nixpkgs does not carry.

## Intent

Omarchy's source is packaged, not reimplemented. `OMARCHY_PATH` points at it in
the store and only the distro-coupled scripts — the ones that run `pacman` — are
replaced or shimmed. Tracking an upstream release is a source bump, not a
re-port, and that property is worth more than any individual fix.

| path | what it is |
|---|---|
| `omarchy/` | the vendored tree, its patches, and `nix-bin/` — the replacements |
| `omarchy/nix-bin/` | commands that replace an Arch-coupled upstream one |
| `omarchy/skills/` | what an agent on a nixarchy machine reads |
| `apps/` | packages with no nixpkgs equivalent |
| `doctor.sh`, `verify.sh`, `review.sh` | scripts spliced into derivations at build time |
| `explain.sh` | reads a Nix failure and says what it is, in the user's vocabulary |
| `box.nix`, `microvm.nix` | the container and guest runners |

## The trap that has cost the most here

**`writeShellApplication` builds a strict PATH from `runtimeInputs`.** A command
a script calls and does not declare is a runtime failure no build catches — and
it does not read as "missing command", it reads as whatever the script concludes
from the failure.

`doctor.sh` carries the canonical example in a comment on its `runtimeInputs`:
an undeclared `vainfo` does not report "vainfo is missing", it reports "no VAAPI
driver answered", which is a different and much worse answer to hand someone. It
ran anyway during development, from the author's own PATH.

Before adding a command to any script here, add it to that derivation's
`runtimeInputs`. If the script parses JSON, that means `jq` — reaching for `sed`
on JSON is how a check starts confidently reporting wrong things the first time
nix reformats a file.

## `writeShellApplication` also sets `errexit`

The `runtimeInputs` trap above is the expensive one. This is its sibling, and
it cost an hour here: the wrapper is `set -o errexit -o nounset -o pipefail`,
so a script that runs fine as `bash pkgs/thing.sh` can die at the first
command substitution once it is packaged.

`nixarchy explain -- <command>` did exactly that. `err=$("$@" 2>&1)` captures
the output of a command that is failing — that is the entire point of the
form — and under `errexit` the script exited there, before printing anything,
with the wrapped command's status. Which reads as the tool never having run.
`err=$("$@" 2>&1) || status=$?` is the fix; a script's own `set -uo pipefail`
does **not** turn `errexit` back off.

The general shape: **anything that deliberately runs a failing command has to
say so at the call site.** And a script whose whole job is to be handed
failures is one where every path is that path — so exercise the packaged
binary, not the source file. The bug survived a green check suite because
every assertion fed the script on stdin, and stdin never fails.

## Patching upstream

Everything is patched with `--replace-fail`, so an Omarchy bump that rewords a
line a patch depends on **fails the build** rather than quietly restoring Arch
instructions. Only `SKILL.md` and `contributing.md` are replaced outright, where
the guidance is wrong here rather than merely misspelt.

CI additionally asserts that no skill code block contains a `pacman`, `yay`,
`/usr/share/omarchy` or Arch-debuginfod line. Prose may contrast with Arch on
purpose; a fenced block is what an agent copies.

## Tests

| check | covers |
|---|---|
| `omarchy` | the tree builds, and the README's counts still match it |
| `omarchy-runtime` | the replaced commands run |
| `patched-files` | every `--replace-fail` patch still applies |
| `etc-overlay` | the 40 files of upstream's `/etc` tree are each classified in `data/etc-overlay.nix` — the rows classed `installed` are what `modules/nixos.nix` puts in `/etc`, and the manifest is where "ignored on purpose" is written down for the rest |
| `doctor-graphics` | the doctor's GPU rules, against fixture machines |
| `doctor-ldd` | the doctor's dynamic-link check, against binaries built broken |
| `dashboard-clock` | the install dashboard against a rewound clock |
| `explain` | the error explainer, against errors produced inside the check |
