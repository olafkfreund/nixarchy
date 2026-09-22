---
status: approved
issue: 877
intent: intent/2026-09-22-877-manifest-has-kind.md
---

# Spec: keep-loaded plugins keep their shell API across settings changes

## Design

### The patch

In `pkgs/omarchy/default.nix`, next to the #749 `shell.qml` patch and in the same
build phase, one `substituteInPlace` with `--replace-fail` on
`$out/share/omarchy/shell/shell.qml`. It replaces exactly upstream's three lines
(4.0.4, `shell.qml:349`):

```qml
  function manifestHasKind(manifest, kind) {
    return !!manifest && Array.isArray(manifest.kinds)
      && manifest.kinds.indexOf(kind) !== -1
  }
```

with:

```qml
  function manifestHasKind(manifest, kind) {
    // nixarchy CARRIED patch (#877): kinds read through a QML property is a Qt
    // sequence, for which Array.isArray is false; accept anything list-shaped.
    var kinds = manifest ? manifest.kinds : null
    return !!kinds && typeof kinds.length === "number"
      && Array.prototype.indexOf.call(kinds, kind) !== -1
  }
```

The whole function, signature included, is the `--replace-fail` needle. An
upstream bump that rewords it fails the build instead of silently dropping the
fix: the `pkgs/AGENTS.md` rule for every patch here.

The Nix comment above it follows the #749 block's shape:

- what breaks, and the evidence (the razer log);
- **CARRIED, and meant to be dropped** (`AGENTS.md` §11), with the upstream report
  named;
- "Delete it the moment upstream reads `kinds` without `Array.isArray`."

`Array.prototype.indexOf.call` works on real arrays and on Qt sequences alike. The
function returns the same boolean as before for every input where the old code was
right, so the capability profile, `prunePluginApis` and the revoke logic are
untouched.

### The check: `tests/manifest-has-kind.nix`

A behavioural check, not a grep: it runs the patched function in a real QML engine.

1. It takes `manifestHasKind` from the **built** tree
   (`${omarchy}/share/omarchy/shell/shell.qml`), from the line with
   `function manifestHasKind` to the first line that is only `  }`, so it tests
   what ships, patch included.
2. It writes a probe `Item` that embeds that function, with
   `property list<string> kindsList: ["menu", "bar-widget"]`. Read back, that is a
   Qt sequence where `Array.isArray` is false, verified with qtdeclarative 6.11.2 in
   an offscreen run.
3. `Component.onCompleted` asserts four things, and exits through `Qt.exit(code)`.
   The `qml` tool swallows console output in this environment; exit codes are
   reliable. The four:
   - a sequence `menu`: true;
   - a plain JS array `menu`: true;
   - a sequence `bar`: false;
   - a missing manifest: false.
4. Run with `QT_QPA_PLATFORM=offscreen qml probe.qml`. Exit 0 passes; anything else
   fails, naming the assertion that broke.
5. **It carries its own negative control, as `tests/qml.nix` does.** The same probe
   is run against upstream's unpatched function, taken from the unpatched source,
   and **must fail**. If it passes, the check fails: a probe that cannot tell the
   bug from the fix proves nothing (`AGENTS.md` §1 and §4).

Wired into `flake.nix` `checks` next to `qml`, and into whatever list the
check-coverage guard reads.

### Where it is recorded

- The carried-patch comment in `pkgs/omarchy/default.nix`.
- A line in `docs/internals/` wherever the #749 carried patch is listed, if it is;
  the plan step finds it.
- The upstream report is final with the razer log. The owner files it.

## Alternatives rejected

- **Patching all 18 `Array.isArray(...kinds)` sites:** rejected at approval. Only
  this one is proven; the rest are listed in the upstream report.
- **Re-injecting `shell` after `syncPluginApis`:** rejected at approval, left to
  upstream.
- **A grep-only check that the patched text is present:** it proves the edit, not
  the effect. `--replace-fail` already guarantees the text; the check exists to
  prove the behaviour.
- **Normalising manifests to plain JS before profiling** (`JSON.parse`/`stringify`
  at the call sites): more call sites and a larger carried patch, for the same
  effect.
- **A workaround in nixarchy-podman** (`keepLoaded: false`, or reading `shell.json`
  itself): it fixes one plugin, not the host, and costs Podman its keep-loaded
  behaviour.

## Risks

- **Upstream reformats the function.** The build fails by design; the bump PR
  either re-anchors the patch or drops it if upstream fixed the bug.
- **The check's extraction depends on the function's closing line.** If upstream
  reindents, the extraction may catch the wrong range. The negative control and the
  four assertions then fail loudly, not silently.
- **The `qml` tool needs a platform:** `offscreen` works in the Nix sandbox, as it
  did headless here. If a builder lacks it, the check fails. It never silently
  passes.
- **Changed behaviour:** none beyond the bug. Plugins that were never keep-loaded
  never noticed; keep-loaded ones stop losing their API.

## Verification

- The new check **fails** on `main`'s omarchy, from the negative control run as the
  real case, and passes with the patch. The failing output goes in the PR.
- `nix flake check` passes, including `patched-files`, which now also lists
  `shell/shell.qml` for this patch, and `qml`.
- **Live on razer:** the built omarchy tree is installed the way a rebuild would,
  through the nixos_config deploy after the merge. Then:
  - open the Podman menu;
  - `omarchy bar set nixarchy.podman showStats false --json`;
  - open the menu again: the CPU and memory meters are gone, with no shell restart;
  - `qs log` shows no revoke for `nixarchy.podman`, via temporary instrumentation
    again if needed, never committed;
  - `shell.json` is restored afterwards.
- Follow-up in nixarchy-podman, a separate small PR: drop the "restart the shell"
  sentence from `docs/usage.md` once razer confirms.
