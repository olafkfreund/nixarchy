            // Right opens a submenu or follows a link, and never runs a row (#1305).
            if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter && !root.rightEnters()) return
