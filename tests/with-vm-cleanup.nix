lib: script:
''
  ${builtins.readFile ./vm-cleanup.py}

  owned_vms = []

  def create_owned_machine(start_command, *, name=None, keep_machine_state=False):
      # StartCommand uses shell=True; own qemu rather than a waiting shell.
      machine = create_machine("exec " + start_command, name=name,
                               keep_machine_state=keep_machine_state)
      owned_vms.append(machine)
      return machine

  try:
''
+ lib.concatMapStrings (line: "    ${line}\n") (lib.splitString "\n" script)
+ ''
  finally:
      reap_owned_vms(owned_vms)
''
