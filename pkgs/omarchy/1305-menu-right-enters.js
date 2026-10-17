  // Right opens a submenu or follows a link, and never runs a row (#1305).
  function rightEnters() {
    if (root.dmenuActive || !root.cursorActive) return false
    if (root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return false
    var kind = displayModel.get(root.selectedIndex).kind
    return kind === "menu" || kind === "link"
  }
