if [[ ${1:-} == "use" ]]; then
  packages=(podman crun)
  if omarchy-hw-nvidia; then
    packages+=(nvidia-container-toolkit)
  fi

  if [[ " $* " == *" --detach "* ]]; then
    # The agents panel starts a setup in the background, with no terminal to
    # ask for a password in, so polkit asks for it instead. The panel shows
    # the setup's row while this runs and reads the reason from the Error
    # line; pkexec's 126 is the password dialog dismissed, passed on as is.
    if omarchy-pkg-missing "${packages[@]}"; then
      echo "Installing ${packages[*]}"
      pkexec /usr/bin/pacman -S --noconfirm --needed -- "${packages[@]}"
      status=$?
      if (( status == 126 )); then
        echo "Error: Authentication was cancelled"
        exit 126
      elif (( status != 0 )) || omarchy-pkg-missing "${packages[@]}"; then
        echo "Error: Couldn't install ${packages[*]}"
        exit 1
      fi
    fi
  else
    omarchy-pkg-add "${packages[@]}" || exit 1
  fi
fi
