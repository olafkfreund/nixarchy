---
status: draft
issue: 1032
intent: intent/2026-09-28-1032-notification-sender-close.md
---

# Spec: a notification closed by its sender leaves the screen

## The open questions, settled

1. **History: a sender's close archives the toast, exactly like dismiss and
   expire.** Omarchy's own code already decides this. `removePopup()`
   (`Service.qml:321`) says *"The popup is leaving the screen — for any
   reason — so its file must not survive to the next shell restart. It
   becomes the newest history entry instead."* A sender's close is one more
   reason. The alternative, `removePopupsByOriginalId()` (`:301`), which the
   issue suggested, *deletes* the popup's file with no history entry. That
   function exists for replacement, where "history would otherwise hold two
   entries for what the sender means as one notification". Using it here
   would add a second rule to a file whose author wrote down one, and a fix
   that follows upstream's own rule is the one upstream is likely to take.
   *This is a judgement call and the thing to push back on if you disagree.*
   "Retracted means gone from history too" is defensible (GNOME does it).
2. **The probe fits in `checks.session`, and needs no new IPC.** Each popup
   on screen has a file under `~/.local/state/omarchy/notifications/`
   (`persistPopupFile`, `:498`). `removePopup` moves it to
   `notifications/history/` (`archivePopupFileFor`, `:538`). With the bug
   the file stays where it is. Both locations are ordinary files the test
   can read.

## Design

### The fix: act on `CloseRequested`, through `removePopup`

Quickshell's `Notification.closed` carries a reason. Confirmed in
Quickshell's source: a sender's `CloseNotification` gives `CloseRequested`
(`server.cpp:140`), `dismiss()` gives `Dismissed`, and `expire()` gives
`Expired` (`notification.cpp:65-66`). The handler at `Service.qml:165`
becomes:

```qml
notification.closed.connect(function(reason) {
  if (service.liveRefs[snapshot.originalId] !== notification) return
  delete service.liveRefs[snapshot.originalId]
  if (reason !== NotificationCloseReason.CloseRequested) return
  Qt.callLater(function() {
    for (var i = popupModel.count - 1; i >= 0; i--) {
      var row = popupModel.get(i)
      if (row && row.originalId === snapshot.originalId && !isRestoredRow(row))
        removePopup(i, "close")
    }
  })
})
```

Why each line is the way it is:

- **The existing guard stays first.** A newer notification may have taken
  over this id, and its popup must not be removed by the old object's close.
- **`liveRefs` is cleared before `removePopup`.** `removePopup` looks up the
  live object to call `dismiss()` on it. With the reference gone it finds
  nothing and does not send a second close back to a sender that just closed
  it.
- **Only `CloseRequested`.** Dismiss and expire already remove their popup
  through `removePopup`, and their own `closed` then fires with `Dismissed`
  or `Expired`. Acting on those too would try to remove a row that is
  already gone. That is harmless but wasteful, and the explicit reason check
  says what the handler is for.
- **`Qt.callLater`**, because the file already notes that mutating
  `popupModel` while a Repeater is incubating crashes (`:188-189`).
- **`isRestoredRow` rows are skipped**, for the reason `removePopupsByOriginalId`
  gives: a restored row's old id may now belong to someone else.

### Carried as a patch

`pkgs/omarchy/902-notification-sender-close.patch`, applied the way
`901-bar-keyed-layout.patch` is. If an Omarchy bump rewords the handler, the
patch stops applying and the build fails, which is the signal to drop it
once upstream has fixed it.

### Reported upstream

An issue at `omacom/omarchy` with the reproduction from #1032 and this
handler as the suggested fix. **Drafted in the PR and posted only after the
owner has read the exact text and said go.**

### The probe: `checks.session`

After the session is up, as the logged-in user:

1. `notify-send -u critical -p -a probe -- "close me" ""`, capturing the id.
   Critical is the worst case, because no timer will ever remove it.
2. Wait for a popup file to appear under `notifications/` whose content
   names the summary. This proves the toast is on screen before anything
   else is asserted.
3. `busctl --user call org.freedesktop.Notifications
   /org/freedesktop/Notifications org.freedesktop.Notifications
   CloseNotification u <id>`.
4. **The property:** that file leaves `notifications/` and appears in
   `notifications/history/`, within a timeout measured on the first run.

Step 4 has two halves, and both change with the bug. With the bug, the file
stays under `notifications/` and never reaches `history/`. With the history
decision reversed, it would leave `notifications/` and not reach `history/`.
So this assertion also pins decision 1.

## Alternatives rejected

- **`removePopupsByOriginalId` (the issue's suggestion):** deletes history.
  See decision 1.
- **Acting on every `closed`:** double-removes on dismiss and expire. It
  works, but it hides what the handler is for.
- **Asserting on a screenshot:** the popup file *is* the shell's record of
  what is on screen (it exists to restore on-screen toasts after a restart),
  and OCR in a software-rendered VM is the flakiest tool available.
- **Patching only, no upstream report:** every Omarchy bump re-applies it.
- **Upstream only:** leaves critical notifications stuck for however long
  that takes, which nixarchy-voice is already working around.

## Risks

- **The popup file is a proxy for "on screen".** It's a close one, because
  the file exists precisely for on-screen toasts. It's still the arrangement
  and not pixels, so the first red run must show the file staying put *with
  the toast visibly still there*, which a screenshot in the failing run can
  confirm once.
- **Quickshell version.** The enum was read from a Quickshell source tree in
  the local store. The plan confirms it is the version nixarchy runs (the
  overlay pins 0.3.1 when nixpkgs is older).
- **DND.** A silenced notification never gets a popup. The probe must run
  with Do Not Disturb off, and assert that, or it passes by never showing
  anything.
- **`checks.session` gets one more block.** It is seconds of work, but in a
  VM check that every PR runs.

## Verification

| what | how | break it by |
|---|---|---|
| the patch applies | `nix build .#omarchy` | an Omarchy source that rewords `:165` fails the build |
| the fix works | the `checks.session` block above | removing the patch: the file stays under `notifications/` and the block fails |
| history decision pinned | the same block's `history/` half | swapping to `removePopupsByOriginalId`: no history file, so it fails |
| dismiss/expire unchanged | existing session coverage, plus `dismissAll` over IPC leaving history intact | — |
| real machine | the #1032 reproduction on razer after deploy | — |
