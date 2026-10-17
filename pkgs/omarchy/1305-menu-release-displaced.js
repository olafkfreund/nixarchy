  // A request the next one displaces is cancelled, or its caller waits for ever (#1305).
  function releaseDisplacedRequest() {
    if (root.requestActive && root.doneFile)
      Quickshell.execDetached(["sh", "-c", ": > \"$1\"", "sh", root.doneFile])
  }
