    // Read-only panel state, inserted into shell.qml's `shell` IpcHandler.
    //
    // Nothing here computes anything: shell.qml's own isPluginOpen() already
    // answers both questions, because toggle() needs it to decide which way to
    // go. It was simply not reachable over IPC, so anything driving the
    // desktop could only find out whether a panel opened by taking a
    // screenshot -- expensive enough that callers skip it and proceed on
    // assumption (nixarchy#749).
    //
    // A fragment rather than an inline --replace-fail string: the replacement
    // has to reproduce shell.qml's own indentation exactly, and a Nix ''
    // string strips its common prefix, so the pattern silently stops matching
    // the moment the file is reformatted.

    // "true", "false", or "unknown" when no plugin answers to that id.
    // Distinguishable from a closed panel on purpose: a caller that misspells
    // an id must not read the answer as "it did not open".
    //
    // The membership test is what makes "unknown" reachable. resolveEnabledId
    // ECHOES a non-matching id back -- it ends `return key`, the canonicalised
    // input, rather than "" -- so a `!resolved` check never fires and every
    // typo answered "false". Found by running it, not by reading it.
    function isOpen(id: string): string {
      // Empty is rejected BEFORE resolving, not after. resolveEnabledId("")
      // canonicalises to "" and then matches the first enabled plugin whose
      // clonedFrom is also "" -- which is most of them -- so an unset shell
      // variable would resolve to an arbitrary panel and be answered about.
      var wanted = String(id || "")
      if (!wanted) return "unknown"
      var resolved = shell.pluginRegistry.resolveEnabledId(wanted)
      if (!resolved || !shell.pluginRegistry.installedPlugins[resolved])
        return "unknown"
      return shell.isPluginOpen(resolved) ? "true" : "false"
    }

    // Every open panel, as a JSON array of ids. Sorted, for the reason
    // listPlugins gives above: consumers should not each invent their own
    // presentation order.
    function openPanels(): string {
      var out = []
      var plugins = shell.pluginRegistry.installedPlugins
      for (var id in plugins) {
        if (shell.isPluginOpen(id)) out.push(id)
      }
      out.sort()
      return JSON.stringify(out)
    }

