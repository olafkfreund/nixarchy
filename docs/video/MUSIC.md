# The promo video's music, and what posting it obliges

`nixarchy.mp4` in this directory is the **clean** cut: no audio stream at all,
which is why it can sit on the front page with no attribution attached to it.

The **social** cut — the same 60 seconds with captions and a music bed, for
Reddit, Discord and the like — is not in this repository. It is 13 MB and it
is for posting rather than for hosting, and the repository already carries the
clean cut plus a poster. But it carries an obligation, and that is what this
file is for: an obligation recorded only on the machine that produced the file
is one nobody can honour a year later.

## The required attribution

The bed is licensed **CC BY 4.0**, which requires credit. Wherever the social
cut is posted, the description needs this line:

    Music: "Tame the Beast" by LOFI LION, licensed under CC BY 4.0.
    https://creativecommons.org/licenses/by/4.0/

| | |
|---|---|
| Track | "Tame the Beast" |
| Artist | LOFI LION |
| Licence | Creative Commons Attribution 4.0 International |
| Licence text | https://creativecommons.org/licenses/by/4.0/ |
| Obtained from | https://archive.org/details/lofi-lion-tame-the-beast |
| Original source named there | https://youtu.be/d74r-eI7UuM |
| Retrieved | 2026-09-24 |

## The provenance caveat — read before posting

The archive.org item is a **re-upload**. Its `creator` field is null and the
licence is asserted by the uploader, who links a YouTube video as the original.
That is second-hand: it is not the artist publishing under a licence they hold,
it is a third party stating that they did.

This is weaker than the approved spec asked for, which wanted an
attribution-not-required track from the YouTube Audio Library — a source that
needs a Google login and cannot be reached from a script. The spec also named
this exact risk: *"Content ID can flag a permissively licensed track. The
licence page is saved beside the audio."* This file is that saving. If the
track is ever challenged, the chain above is the evidence, and the honest
answer is that one link in it was not verified against the artist directly.

A CC0 candidate was rejected for a related reason and it is worth knowing why:
the track was tagged `vaporwave` and `cursed signalwave`, a genre built from
sampled broadcast material. **An uploader's CC0 declaration cannot launder
samples they did not own.** The same search returned a twenty-one-pilots remix
claiming CC0, which it legally cannot be — so "the page says CC0" is worth very
little on its own.

## If that is not good enough

Two stronger options, neither expensive, because the music is a post-production
step that needs no re-recording:

- confirm the licence from LOFI LION's own channel or site and record that URL
  here instead of the archive.org one;
- use no bed, or one generated from scratch, which nobody can claim.

Re-cutting is one command against the existing master:

```sh
SCREENCAST_MUSIC=/path/to/track.mp3 screencast-edit <take-dir>
```

`tests/demo/screencast/edit.nix` does the mixing: ducked to 12%, faded in over
1.5 s, normalised to −14 LUFS, which is what the platforms normalise to anyway.
Take 5 measured −13.4 LUFS integrated.

The decision is a publishing one rather than a technical one, and it is the
owner's.
