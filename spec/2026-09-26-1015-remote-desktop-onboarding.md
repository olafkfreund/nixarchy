---
status: draft
issue: 1015
intent: intent/2026-09-26-1015-remote-desktop-onboarding.md
---

# Spec: Remote desktop you can turn on everywhere, and reach from the menu

## Decisions carried in from the approved intent

Answered by the approver, and treated as settled here:

| Question | Decision |
|---|---|
| Q1 one password or one per machine | **per-host passwords**, as today |
| Q4 bar widget, menu row, or both | **menu row.** No bar widget |
| Q6 outbound shape | **SSH tunnel only.** No other reach is offered |

Q2, Q3 and Q5 were left open and are settled below, with reasons, because the
research changed what they mean.

## The premise that changed: the menu is not QML

The intent and the request both say "QML shell menu". The omarchy menu is not
QML. It is `omarchy-menu.jsonc`, a file of rows

    "setup.local-ai": {"icon":"󰭹","label":"Local AI","aliases":["ollama","local model"],
                       "action":"omarchy-launch-floating-terminal-with-presentation nixarchy-local-ai"},

which this repository already extends from `pkgs/omarchy/default.nix` --
`askMenuRows` at line 142 is nine of them, and `antigravityMenuRow` is one
more. A row's `action` is a shell command, run in a floating terminal; `when`
hides a row whose precondition is unmet, and `checked` renders a toggle.

QML in this tree is something else: `pkgs/rebuild-panel/` and the three files
under `pkgs/omarchy/*.qml` are Quickshell **bar widgets and panels**, which is
the thing the approver has just ruled out.

So the deliverable is a menu row and a `gum` wizard behind it, in the shape of
`nixarchy-local-ai`. That is less code than a QML panel and can do three things
a QML panel cannot: hand off to `$EDITOR` for `sops edit`, prompt for sudo, and
print a diff of what it is about to change. **If the approver wants a Quickshell
panel specifically, this spec is wrong and should be rejected here rather than
at the plan.**

## Design

Four pieces, no new mechanism in any of them.

### 1. `nixarchy secret enroll` -- `pkgs/secret.nix`

A sixth verb beside `new`, `edit`, `remove`, `list`, `where`, `copy`. It adds
the machine it runs on to an existing `.sops.yaml` and stops there.

`ensure_policy` (lines 289-331) keeps both existing behaviours: it writes the
file whole when absent, and it still returns success when a rule for this host
is already present. What changes is the third branch. Today it `fail`s and
prints a block to paste; with `enroll` it prints that block *and* names the
command that will apply it. `enroll` is the only thing that ever writes into an
existing policy, so the refusal stays the default and the write is something
the user asks for by name.

The write is **structural, not textual**. `yq-go` appends to `.keys` and
`.creation_rules`, so no regular expression ever decides where a rule goes --
which is the whole reason the current code refuses. Two consequences worth
stating:

- **Enrolled hosts get their recipient written inline, not as a YAML anchor.**
  The hand-written first host keeps its `- &host age1...` / `- *host` pair,
  because it is already there and rewriting it would be the churn this avoids.
  New hosts get the literal recipient in the key group. Anchors are the part of
  YAML that round-trips worst, and a policy file that sops cannot parse is a
  machine whose secrets will not decrypt.
- **It is idempotent by reading, not by guessing.** `enroll` on a host already
  in the policy is a no-op that says so.

`enroll` refuses, as `new` does, when there is no SSH host key: the recipient is
derived from it and it does not exist until sshd has run once.

### 2. `nixarchy-remote` -- `pkgs/omarchy/nix-bin/nixarchy-remote`

A `gum` wizard, in the shape of `nixarchy-local-ai`, with two verbs.

**`nixarchy-remote serve`** -- incoming, on this machine. It reports the four
states that matter and offers the next step for whichever is unmet: is sshd on
(the host key depends on it), is there a secret named `hypr-rdp-password`, is
the service enabled, is the unit running. It runs `nixarchy secret enroll` and
`nixarchy secret new` on the user's behalf.

It does **not** edit `hosts/<host>/configuration.nix`. The two lines that
declare the secret and point the service at it are printed with the exact path
they belong in, and the reason is the one already written into
`docs/manual/remote-desktop.md`: they cannot go in the menu's own
`services.nix`, because `nixarchy apply` copies that file into
`hosts/<host>/nixarchy/` and a relative `./secrets.yaml` written there resolves
one directory too deep. Editing a user's `configuration.nix` by pattern-matching
is the same hazard as splicing `.sops.yaml`, and the same answer applies.

This is Q2, settled at the middle rung: the wizard does every step that is
mechanical, and hands over the one step that is an edit to a file we do not own.

**`nixarchy-remote connect`** -- outbound. Lists candidate machines, opens
`ssh -L <port>:localhost:3389 <host>` and starts the client against
`localhost:<port>`. The forward is on a free local port rather than 3389, so
connecting to a second machine does not collide with the first.

**Q3, the machine list, settled:** the sources are `~/.ssh/config` `Host`
entries and, when `tailscale` is on PATH, `tailscale status --json` peers,
merged and deduplicated. Nothing is probed. With tunnel-only as the reach, the
precondition for connecting is that SSH already works, so the SSH config is the
list of machines the user can actually reach -- and the tailnet supplies the
names of machines they have not yet given an SSH entry. A list held in the
config repo was rejected below.

The wizard never claims a machine is reachable. It offers a list of machines
you could try, and says plainly that hypr-rdp serves a session that is already
logged in -- so a machine with nobody at it has nothing to connect to.

### 3. Menu rows -- `pkgs/omarchy/default.nix`

A `remoteMenuRows` fragment beside `askMenuRows`, written with the same
`builtins.toFile` for the same reason (JSON containing shell, and every layer
between there and the file wants to escape something different):

    "setup.remote"          Remote desktop        -- parent
    "setup.remote.serve"    Allow connections     -- nixarchy-remote serve
    "setup.remote.connect"  Connect to a machine  -- nixarchy-remote connect

`setup.remote.connect` carries a `when` gating it on an RDP client being on
PATH. A row that offers to connect with no client is §2's defect exactly:
something we ship naming something that does not exist.

### 4. The client -- `data/apps.nix`

There is no RDP client anywhere in this tree today. `freerdp` goes in the app
catalogue as an opt-in entry rather than into `pkgs/omarchy/default.nix`'s
runtime list, because it is only needed by the machine doing the connecting and
the `when` gate above already makes its absence honest rather than broken.

### Also changed

- `data/bin-ledger.nix` -- a row for `nixarchy-remote`, class `new`
- `docs/manual/remote-desktop.md` -- the enrollment path and the menu rows;
  the manual stops being the only place the process exists
- `docs/manual/secrets.md` -- `enroll` in the verb list

Nothing in `modules/services/hypr-rdp.nix` changes. Neither refusal is touched,
which is the intent's first constraint.

## Alternatives rejected

**A Quickshell QML panel.** What was asked for by name, and rejected on
research: the menu is JSONC and shell, so a panel would be a second, parallel
surface rather than the menu the user meant. It also cannot run `sops edit` in
`$EDITOR`, cannot prompt for sudo, and would have to reimplement `gum`'s
prompts in QML. Reversible -- if a panel is wanted later it can front the same
`nixarchy-remote` verbs.

**A bar widget.** Ruled out by the approver. It is also the wrong shape: the
rebuild panel earns a bar slot by drawing nothing until a rebuild is running,
and remote desktop is something you go looking for.

**One shared secret for the fleet.** Ruled out by the approver. It would have
been one `sops edit` and one rotation, at the cost of one compromised machine
being every machine's desktop.

**Splicing `.sops.yaml` with `sed`.** The reason is already in the file:
a creation rule edited by pattern-matching is one that can silently stop
matching, and the failure surfaces as a secret that will not decrypt, long
after the edit.

**Editing the user's `hosts/<host>/configuration.nix`.** Same hazard, same
answer, and the target is a file whose shape we do not control.

**Probing port 3389 to build the machine list.** It answers "something is
listening", which is not "your desktop is there", and it makes opening a menu a
port scan of the tailnet.

**A list of RDP machines in the config repo.** It would know which hosts serve
RDP, which neither other source does -- and it is a hand-maintained list of
things that exist elsewhere, which §4 says fails open. The SSH config is
already maintained for another reason.

**Bundling `freerdp` into the omarchy runtime list.** It would be on every
machine including the ones only ever connected *to*, for a row most users never
open.

## Risks

- **`yq-go` rewriting `.sops.yaml` in a way sops rejects.** The worst outcome
  in this spec: the file decides whether anything decrypts. Mitigated by
  writing recipients inline rather than as anchors, and by the verification
  below, which re-encrypts and re-decrypts after every write rather than
  diffing the YAML.
- **A wizard that makes turning RDP on feel like one click.** The service is
  arranged around refusing to serve an unauthenticated desktop; a smoother path
  to `enable = true` must not become a smoother path past the password. The
  `serve` verb reports the secret as a required state, not an optional one.
- **The list implying reachability.** Named in the design; carried as wording,
  which no check can enforce.
- **`enroll` run on a machine whose host key has changed** (a reinstall keeping
  the hostname) adds a second recipient under the same name. It should be
  detected and reported rather than appended.
- **Menu rows are parsed at runtime**, so a JSONC error is a menu that does not
  open. `pkgs/omarchy/default.nix` already parses the generated file at build
  time for this reason, and the new fragment goes through it.

## Verification

Every check below states how it is made to fail first, per §1. The failing
output goes in the PR.

| what | how | break it by |
|---|---|---|
| `enroll` adds a second host and both can still decrypt | new `tests/secret-enroll.nix`: a fixture `.sops.yaml` with host A, encrypt a value, run `enroll` as host B, assert **both** identities decrypt it after `sops updatekeys` | dropping the `.creation_rules` append -- B's identity must then fail to decrypt |
| `enroll` is idempotent | same check, run twice, assert one entry | removing the already-present test -- the second run must produce a duplicate |
| `enroll` refuses with no host key | same check, no key present, assert non-zero and a message naming sshd | removing the guard -- it must then produce a policy with an empty recipient |
| the menu rows name verbs that exist | `tests/menu-verbs.nix`, already written, already run | misspelling `enroll` in the row -- it must name the row and the verb |
| the generated menu still parses | the build-time parse in `pkgs/omarchy/default.nix` | an unbalanced brace in the fragment |
| `nixarchy-remote` declares what it invokes | `writeShellApplication` `runtimeInputs`; `pkgs/verify.sh` for the hardware half | removing `gum` from `runtimeInputs` |
| the ledger classifies the new command | `.github/scripts/check-bin-ledger.py`, already run | omitting the row -- it must report the file unclassified |

**What no layer here can reach**, stated rather than papered over (§3): an
actual RDP connection between two machines. `checks.session` boots one desktop,
not two, and the tunnel needs a second host with a logged-in session. This goes
in `tests/install-matrix.py` as a named hole and in `pkgs/verify.sh` as a manual
step, because a documented hole gets tested by a human and an undocumented one
gets tested by a user.

## Open questions

1. **Is `freerdp` the client?** It is the obvious CLI answer and `wlfreerdp`
   suits a Wayland session. A GUI client such as Remmina would suit a user who
   wants saved connections, at the cost of a second place to configure things.
2. **Does `connect` belong in this issue at all?** It is the half that needs a
   new package and has the weakest verification story. Splitting it out would
   let `serve` plus `enroll` -- the fleet onboarding that was actually asked for
   -- ship on its own checks. I lean towards splitting; it is the approver's
   call.
