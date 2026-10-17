    + '__omarchy_pkg_has() { local c=${1%-bin}; c=${c%-stable}; '
    + 'command -v "$1" &>/dev/null || command -v "$c" &>/dev/null; }\n'
