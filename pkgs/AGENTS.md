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

## A long build phase is one indented string, and it strips one indent

`pkgs/omarchy/default.nix`'s `installPhase` is a single `'' ... ''` string, and
Nix removes the *smallest* indentation shared by every line in it, once, for
the whole string. One line anywhere with less indent (a multi-line
`--replace-fail` argument sitting at four spaces) means everything else keeps
sixteen. So a heredoc added at the phase's usual depth fails twice: its
`EOF` is never at column 0, so it never ends, and inline Python gets
indentation it did not ask for (#764). Put anything more than a line or two of
code in its own file beside `default.nix`, as `check-logo.py` and
`nixarchy-plymouth-frames.py` are, and call it with `python3 ${./file.py}`.
That also avoids escaping `\n` and `${` inside the string.

**Counting columns of the banner art counts bytes in the builder.** Every block
glyph is three bytes of UTF-8, and the sandbox's locale is C, so `awk
length()` and `wc -c` read an 87-column banner as roughly 250. Count
characters (`len()` in Python with `encoding="utf-8"`).

## `writeShellApplication`'s bash has no `compgen`, and an `if` hides that

The shell it wraps is nixpkgs' plain `bash`, not `bashInteractive`, and that
build has no programmable completion, so `compgen` does not exist. A script
that works in your terminal fails when packaged. Inside an `if`, the failure
does not even stop the script under `errexit`: `if compgen -G "$dir/*"` reads
"command not found" as a false condition. #762's volume guard did exactly that,
so it let every case through, and only the check saw it. Use a glob loop
(`for f in "$dir"/*; do [ -e "$f" ] && ...`) or `find`. The same goes for any
builtin you learned in an interactive shell: run the packaged binary, not the
source file.

## Patching upstream

Everything is patched with `--replace-fail`, so an Omarchy bump that rewords a
line a patch depends on **fails the build** rather than quietly restoring Arch
instructions. Only `SKILL.md` and `contributing.md` are replaced outright, where
the guidance is wrong here rather than merely misspelt.

CI additionally asserts that no skill code block contains a `pacman`, `yay`,
`/usr/share/omarchy` or Arch-debuginfod line. Prose may contrast with Arch on
purpose; a fenced block is what an agent copies.

### Aether's lockfile

Kept because the patch it describes came off at 4.29.9 and may have to go back
on, and because the shape generalises to any `buildNpmPackage` here.

Upstream's `frontend/package-lock.json` was out of sync with its
`package.json`, so `npm ci` — which `buildNpmPackage` uses, correctly, being
the only npm mode that installs exactly what is locked — refused outright:

    npm error `npm ci` can only install packages when your package.json and
    package-lock.json ... are in sync.
    npm error Missing: @emnapi/core@1.11.3 from lock file
    npm error Missing: @emnapi/runtime@1.11.3 from lock file

Those are optional native transitive dependencies npm omits when the lock is
generated on another platform. Regenerating needs a network, which a sandboxed
build has not got, so the corrected lock was carried as a patch, produced with
`npm install --package-lock-only` against the tagged source.

**The part worth keeping.** It was applied to the *source*, with
`applyPatches`, and not inside `buildNpmPackage` — because `fetchNpmDeps` reads
the lock from `src`. A patch applied within the package fetches against the old
lock and builds against the new one, which surfaces as a hash mismatch that
looks like a stale `npmDepsHash` and is not.

**How it retired, and why that took a day.** The patch stops applying when
upstream's lock changes, which is the notification working as designed — but it
fails during `nix run .#update`, which bumps every pinned app in one pass, so
the whole update looks broken rather than one app (#743). Before rewriting such
a patch, check whether it is still needed at all: run `npm ci` against the new
tag's unpatched lock, and against the old tag's as a control. Here the new one
succeeded and the old one failed with the error above, which is what a fix
being unnecessary looks like.

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
