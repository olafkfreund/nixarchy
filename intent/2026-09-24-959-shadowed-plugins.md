---
status: draft
issue: 959
author: olafkfreund
---

# Intent: a hand-cloned plugin that shadows a shipped one should say so

## Problem

A real directory at a declared plugin's id pins that plugin forever, and the
only signal is one line in a journal nobody reads.

`modules/home.nix:1110-1116`, in the activation reconcile step:

```sh
if [ -e "${dir}/$id" ] && [ ! -L "${dir}/$id" ]; then
  echo "nixarchy: ${dir}/$id is your own directory, not replacing it"
else
  if [ "$(readlink "${dir}/$id")" != "$target" ]; then
    run ln -sfn "$target" "${dir}/$id"
  fi
  echo "$id" >> "${staging}"
fi
```

Leaving a real directory alone is correct and must stay: it may be somebody's
working copy. The failure is the case where that directory is **a clone of the
same plugin nixarchy now ships**. It then holds its commit through every
rebuild and every pin bump, and nothing says so.

**Reading the block turned up something the issue does not mention, and it
explains why nothing downstream can notice.** On the shadowed branch the id is
never written to `${staging}`, so it is absent from the manifest -- as far as
nixarchy's own bookkeeping goes, that plugin *was never planted*. There is no
record of an intention that went unmet, which is precisely what a later check
would need in order to find one.

**And nothing consumes the message.** `pkgs/doctor.sh` has no plugin checks of
any kind, and a search of the tree for the behaviour rather than the wording
finds the `echo` and nothing else. So this is not a mechanism to extend; there
is no mechanism.

## What it has already cost

The issue records the herdr case: #787 began shipping `nixarchy.herdr`, #954
bumped the pin to plugin 0.3.0, razer was deployed from it, health checks
passed and 0 units failed -- and razer went on loading **0.2.0**, because
herdr's own development plan had cloned it into
`~/.config/omarchy/plugins/nixarchy.herdr` by hand.

**I audited both hosts today, and the shape is live on six more ids:**

| host | id | on disk |
|---|---|---|
| p620 | `nixarchy.distrobox` | real directory, not a clone |
| p620 | `nixarchy.flatsnap` | real directory, not a clone |
| p620 | `nixarchy.podman` | real directory, not a clone |
| p620 | `olafkfreund.github-actions` | clone, **28 commits AHEAD** of the shipped pin |
| razer | `nixarchy.distrobox` | real directory |
| razer | `olafkfreund.github-actions` | clone at **exactly** the shipped commit |

Those last two rows are the whole design problem, and they point opposite ways:

- **p620's clone is ahead of what we ship.** It is not stale; it is someone's
  working copy carrying 28 commits. Anything that moved it aside automatically
  would have destroyed work.
- **razer's clone is identical to what we ship.** Nothing is wrong today and
  nothing would show. It goes stale the instant that pin moves -- silently, and
  with a green deploy.

So the harm is **latent**: it is invisible at the moment the clone is made, and
it surfaces only as "the fix I shipped is not on the machine".

This also devalues a kind of verification I did earlier today. Checking a pin
bump at the flake level -- lock diff clean, manifest id unchanged, version
moved -- is a true statement about the flake and says **nothing** about what the
machine loads. Section 3's rule, from the other end: the check held the
interesting variable constant.

## Proposed outcome

- A user whose clone shadows a plugin nixarchy ships is **told**, somewhere they
  will actually see it, naming the directory, the commit it is on, the commit
  nixarchy ships, and the one-line fix.
- A user whose directory is their own plugin, or their own fork, keeps today's
  quiet behaviour. Telling them repeatedly about a deliberate choice is how a
  warning gets ignored.
- Nothing is moved, renamed or deleted on the user's behalf.

## Affected users and systems

- Anyone who cloned a plugin by hand before nixarchy shipped it -- which was the
  only way to get it, so this lands on early adopters and on us.
- `modules/home.nix` (the reconcile step). Possibly `pkgs/doctor.sh`, which
  today has no plugin checks.
- Both development hosts, today, on six ids.

## Constraints

- **Must not touch the user's directory.** The current code is right to leave it
  alone and that is not up for revision.
- **Must distinguish a stale clone from a deliberate one**, or it is noise. The
  issue's proposal -- compare the clone's `origin` with the declared plugin's
  source repo -- is the only discriminator suggested so far. p620's
  `github-actions` clone shows it is not sufficient on its own: same origin,
  28 commits ahead, entirely deliberate.
- **A message in activation output is what already failed.** Whatever is added
  has to reach someone who is not reading `journalctl`.
- Section 1: whatever is built must be provable. A check that cannot see a
  shadowed plugin is the thing this issue is about, one level up.

## Open questions

1. **Where should it surface?** The issue suggests `nixarchy doctor` plus a
   desktop notification at first login after a rebuild. Doctor is the natural
   home and has no plugin checks yet, so this would be its first. A notification
   is more likely to be seen and more likely to be resented. Your call whether
   it is one, the other, or both.

2. **What is the discriminator?** `origin` matching alone is not enough --
   p620's case proves it. Candidates, none free:
   - **same origin, and behind the shipped commit** -- would flag p620's
     (ahead, so no) and razer's (equal, so no), and catch the herdr case. But
     "behind" needs the two commits compared, which needs the clone's history to
     contain the shipped one, which a shallow or diverged clone may not.
   - **same origin, and content differs from what we ship** -- cheaper, no git
     needed, but flags razer's identical clone as different the moment a file
     differs for any reason.
   - **same origin at all**, and let the message say what the difference is
     rather than deciding. Noisier, but it never withholds.

   I lean to the third: report the fact and the two commits, let the user judge.
   A discriminator that decides for them is a discriminator that will be wrong
   about somebody's working copy.

3. **Is the missing manifest entry worth fixing separately?** Today a shadowed
   plugin is absent from the manifest, so nothing can later ask "what did we
   mean to plant here?". Recording the intention -- separately from what was
   actually linked -- may be the smaller and more useful change, and may be what
   any check needs to exist at all.

## Not in scope

- Automatic migration. p620's 28-commits-ahead clone is the argument, and the
  issue reaches the same conclusion.
- Anything about how plugins are installed, or the reconcile logic itself.
- The plugin repositories' own READMEs, which are theirs (section 11).
