if [[ ${1:-} == "use" ]]; then
  packages=(podman crun)
  if omarchy-hw-nvidia; then
    packages+=(nvidia-container-toolkit)
  fi
  omarchy-pkg-add "${packages[@]}" || exit 1
fi
