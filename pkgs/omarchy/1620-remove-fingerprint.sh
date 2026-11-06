reader=off
if omarchy-cmd-present fprintd-delete; then
  # Only fprintd-delete's output is captured, so a sudo prompt or refusal stays on the terminal.
  if delete_output=$(sudo sh -c 'fprintd-delete "$1" 2>&1' sh "$fingerprint_user"); then
    # It exits 0 for "deleted" and "nothing to delete", and two readers can print one of each.
    if [[ $delete_output == *" deleted on "* ]]; then reader=deleted; else reader=none; fi
  elif [[ $delete_output == *"No devices available"* ]]; then
    reader=absent
  elif [[ -z $delete_output ]]; then
    echo -e "\e[31mDeleting fingerprints needs administrator rights.\e[0m"
    exit 1
  else
    # fprintd reaches a reader's copy only through the host's files, so they stay for another try.
    echo -e "\e[31mfprintd could not finish deleting $fingerprint_user's fingerprints: $(tail -n 1 <<<"$delete_output")\e[0m"
    echo "Some may already be gone. Press Remove again."
    echo "If fprintd never recovers, this removes the files and leaves any copy on the reader out of reach for good:"
    echo "  sudo rm -rf -- /var/lib/fprint/$fingerprint_user"
    exit 1
  fi
fi

# The answer comes back on stdout, so a refused sudo cannot read as "no files".
if ! had_files=$(sudo sh -c 'if [ -e "$1" ]; then echo 1; else echo 0; fi' sh "/var/lib/fprint/$fingerprint_user"); then
  echo -e "\e[31mDeleting fingerprints needs administrator rights.\e[0m"
  exit 1
fi
if ! sudo rm -rf -- "/var/lib/fprint/$fingerprint_user"; then
  echo -e "\e[31mCould not remove $fingerprint_user's saved fingerprints, so the removal may be incomplete.\e[0m"
  exit 1
fi

if [[ $reader == deleted || $had_files == 1 ]]; then
  echo -e "\e[32mDeleted $fingerprint_user's saved fingerprints.\e[0m"
elif [[ $reader == off ]]; then
  echo "$fingerprint_user has no saved fingerprints on this disk."
else
  echo "fprintd has none on record for $fingerprint_user. A reader that refused an earlier delete may still hold its copy."
fi
case $reader in
absent) echo -e "\e[33mNo fingerprint reader is available now, so any fingerprints stored on the reader itself stay there.\e[0m" ;;
off) echo -e "\e[33mfprintd is not available, so any fingerprints stored on the reader itself stay there.\e[0m" ;;
esac

echo
echo "Disk snapshots taken since you enrolled still hold a copy until they are deleted."
echo "\`sudo snapper -c root list\` shows the boot snapshots."
if [[ $reader != off ]]; then
  echo
  echo "Fingerprint login is still declared. Turn off services.fprintd (fprintAuth follows it), then Apply changes."
fi
