case "$selection" in
    plain) omarchy-pkg-add plain ;;
    code) omarchy-install-editor-vscode ;;
    cursor) omarchy-pkg-add cursor-bin ;;
    zed) omarchy-install-editor-zed ;;
    sublime_text) omarchy-pkg-add sublime-text-4 ;;
    helix) omarchy-install-editor-helix ;;
    vim) omarchy-pkg-add vim ;;
    emacs) omarchy-install-editor-emacs ;;
    nvim) omarchy-pkg-add neovim ;;
    esac || exit 1
