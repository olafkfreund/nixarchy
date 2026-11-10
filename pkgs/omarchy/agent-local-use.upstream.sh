if [[ ${1:-} == "use" ]]; then
  packages=(podman crun)
  if omarchy-hw-nvidia; then
    packages+=(nvidia-container-toolkit)
  fi

  if [[ " $* " == *" --detach "* ]]; then
    # The agents panel starts a setup in the background, with no terminal to
    # ask for a password in. While the packages are missing, a terminal
    # installs them and then hands the setup back to run detached.
    if omarchy-pkg-missing "${packages[@]}"; then
      run=(omarchy-launch-floating-terminal-with-presentation "omarchy-pkg-add ${packages[*]} && omarchy-local-ai ${*@Q}")
    fi
  else
    omarchy-pkg-add "${packages[@]}" || exit 1
  fi
fi
