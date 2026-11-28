case "$selection" in
    plain) echo "Installing $name..."; omarchy-pkg-add plain ;;
    code) omarchy-install-editor-vscode ;;
    cursor) echo "Installing $name..."; omarchy-pkg-add cursor-bin ;;
    zed) omarchy-install-editor-zed ;;
    sublime_text) echo "Installing $name..."; omarchy-pkg-add sublime-text-4 ;;
    helix) omarchy-install-editor-helix ;;
    vim) echo "Installing $name..."; omarchy-pkg-add vim ;;
    emacs) omarchy-install-editor-emacs ;;
    nvim) echo "Installing $name..."; omarchy-pkg-add neovim ;;
    esac || exit 1
