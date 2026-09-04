{ inputs, pkgs }:
# The questions a first-time user actually answers.
#
# ui_interactive() is `[ -z "$answers_file" ] && [ -t 0 ]`, and every other
# harness passes --answers: checks.install does, installer-vm does. So the
# greeter, all six questions, the validation and the summary had never run
# under test -- only the unattended path had. checks.installer-ui covers
# whether a gum widget can be DRAWN (#133); nothing covered whether the wizard
# can be ANSWERED.
#
# --dry-run rather than an install: it asks every question, writes the flake to
# a temp directory and touches no disk. checks.install already proves an
# install is correct, and reinstalling a machine to find out whether a prompt
# re-asks a rejected username is ten minutes for an answer this gets in one.
#
# Driven over the serial line, not the framebuffer. send_chars is qemu's
# virtual keyboard and lands on tty1, whose only readback is OCR; a serial
# console gives send_console for input and wait_for_console_text for output,
# so every assertion here is on text the installer actually wrote rather than
# on a guess at what a screenshot says. That is also why the installer runs as
# a service on /dev/ttyS0 -- test-instrumentation disables the getty there, and
# a unit with StandardInput=tty is how installer/cd.nix starts it on the real
# medium anyway.
let
  install = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.install;
in
pkgs.testers.runNixOSTest {
  name = "nixarchy-installer-wizard";

  nodes.machine = _: {
    environment.systemPackages = [ install ];

    virtualisation = {
      memorySize = 2048;
      # Below ask_device's 8 GiB floor, deliberately. The root disk is not an
      # install target and the wizard must not offer it; making it too small
      # to qualify turns "the list is right" into something this test can
      # assert without pressing arrow keys at an ordering it cannot pin.
      diskSize = 4096;
      # 1 GiB is under the floor as well and 12 GiB is over it, so exactly
      # one device -- /dev/vdc -- may appear on the disk screen.
      emptyDiskImages = [
        1024
        12288
      ];
    };

    # Not wantedBy anything: the test starts it once the machine is up, so a
    # unit that dies during boot cannot be mistaken for a wizard that reached
    # a question and stopped.
    systemd.services.wizard = {
      description = "the installer, on the line the test driver can type at";
      environment.TERM = "linux";
      serviceConfig = {
        # qemu's serial line reports no window size at all -- `stty size` on
        # it answers "0 0" -- and a real serial terminal is the one that has
        # to say. Without this the wizard reproduced #133 on its first gum
        # input: ui_dimension fell past the 0x0 answer to /dev/tty1, took the
        # framebuffer console's 160 columns as confirmed, and centred gum's
        # padding on a number belonging to a different terminal. That is a
        # finding about ui_dimension's fallback chain and it is not this
        # check's subject, so the line is given the size a terminal would
        # have negotiated and the wizard is measured against the console it
        # is actually drawing on.
        ExecStartPre = "${pkgs.coreutils}/bin/stty rows 40 cols 120";
        Type = "idle";
        StandardInput = "tty";
        StandardOutput = "tty";
        StandardError = "tty";
        TTYPath = "/dev/ttyS0";
        TTYReset = true;
        ExecStart = "${pkgs.lib.getExe install} --dry-run";
        Restart = "no";
      };
    };
  };

  testScript = ''
    import datetime as dt
    import time

    machine.wait_for_unit("multi-user.target")
    machine.succeed("systemctl start --no-block wizard")


    def screen(text, seconds=180):
        """Wait for a line the installer printed itself.

        Every anchor used here is a line ui_screen or gum style wrote with a
        newline on the end. That matters: the driver's serial reader iterates
        over lines, so a gum widget's own frame -- which ends on the cursor,
        with no newline -- may sit unflushed for as long as the widget is
        waiting. Anchoring on the heading above the widget rather than on the
        widget itself is the difference between a test that waits and a test
        that hangs.
        """
        machine.wait_for_console_text(text, dt.timedelta(seconds=seconds))


    def gum(widget, previous=None):
        """Block until a gum widget is running AND reading, and return its pid.

        Not a sleep. A fixed wait here is a guess about how fast the VM is, and
        the same guess was wrong twice already in this repo's other tests.

        Two conditions, because the process existing is not the same as the
        process listening: typing at a gum that had started but had not yet
        taken the terminal lost the first characters of the answer, and the
        wizard then sat on a username of "Alwiz" waiting for an Enter that had
        gone to the old line discipline. gum puts the tty in raw mode as it
        starts reading, so `-icanon` on the line is the readiness condition
        that "a process exists" only approximates.

        `previous` distinguishes the input that REJECTED an answer from the one
        it re-asked with, which is what the validation assertions below turn
        on. pgrep -f matches on the whole command line, including that of the
        shell the driver runs this in -- so the pattern is written with a
        bracket that the shell's own copy cannot match.
        """
        reading = "stty -F /dev/ttyS0 -a | grep -q -- -icanon"
        running = f"pgrep -n -f 'gum[ ]{widget}'"
        fresh = "" if previous is None else f' && [ "$p" != {previous} ]'
        machine.wait_until_succeeds(
            f'p=$({running}) && [ -n "$p" ]{fresh} && {reading}')
        return machine.succeed(running).strip()


    def answer(chars):
        r"""Type at the installer, one character at a time.

        Carriage return, not newline. gum puts the terminal in raw mode, where
        Enter is CR -- bubbletea reads a bare LF as ctrl+j and does nothing
        with it, which looked exactly like a wizard hung on its first question.
        The greeter's `read` is in canonical mode and ICRNL turns the same byte
        into the newline it wants, so one form works for both.

        And slowly. qemu's 16550 has a sixteen-byte FIFO and drops what
        overflows it, so a whole answer written in one go arrived at the wizard
        with characters missing -- "wizard" became "Alwiz". This is not a
        guess-the-timing sleep: it is the line's own rate, and the readiness
        conditions above are what the test actually waits on.
        """
        for char in chars.replace("\n", "\r"):
            machine.send_console(char)
            time.sleep(0.05)


    # ---- the greeter ---------------------------------------------------
    # A blank screen accepts Return just as happily as a drawn one, so what is
    # asserted is the text, not that the wizard moved on.
    screen("Omarchy, on NixOS")
    screen("Press Return to start the install")
    answer("\n")

    # ---- keyboard ------------------------------------------------------
    screen(r"Let's set up your keyboard")
    gum("choose")
    # The first entry of installer/brand/keymaps.txt, which is English (US).
    answer("\n")

    # ---- identity ------------------------------------------------------
    screen(r"Let's set up your user account")

    # Two rejections, one per branch of validate_username: a name the regex
    # refuses and a name the regex allows but the system has already taken.
    # Asserting the message is not enough on its own -- an installer that
    # printed the complaint and then carried on with the bad name would pass
    # that -- so each one also waits for a NEW gum input, which only exists
    # because the loop went round again.
    pid = gum("input")
    answer("BadName\n")
    screen("not a usable Linux username")
    pid = gum("input", previous=pid)

    answer("root\n")
    screen("that name is taken by the system")
    pid = gum("input", previous=pid)

    answer("wizard\n")

    # Password, mistyped first: the confirmation exists to catch exactly this.
    pid = gum("input", previous=pid)
    answer("hunter2\n")
    pid = gum("input", previous=pid)
    answer("hunter3\n")
    screen("Those do not match")
    pid = gum("input", previous=pid)
    answer("hunter2\n")
    pid = gum("input", previous=pid)
    answer("hunter2\n")

    # The recovery passphrase, refused first for being the login password.
    #
    # That refusal is the whole reason this is a separate question rather than
    # a reuse of the hash already collected: it goes into the initrd, and the
    # initrd is on the unencrypted ESP. A wizard that accepted the login
    # password here would quietly undo the point of asking.
    pid = gum("input", previous=pid)
    answer("hunter2\n")
    pid = gum("input", previous=pid)
    answer("hunter2\n")
    screen("That is your login password")
    pid = gum("input", previous=pid)
    answer("rescue-me\n")
    pid = gum("input", previous=pid)
    answer("rescue-me\n")

    # Hostname, rejected once for a leading hyphen.
    pid = gum("input", previous=pid)
    answer("-nope\n")
    screen("letters, digits and hyphens")
    pid = gum("input", previous=pid)
    answer("wizardbox\n")

    # Timezone. gum filter opens with --value UTC, so the value is cleared
    # first: three deletes, then a zone typed in full, so what lands in the
    # flake is a value this test chose rather than whatever the fuzzy match
    # happened to rank first.
    gum("filter")
    answer("\x7f\x7f\x7f")
    answer("Europe/London")
    answer("\n")

    # ---- disk ----------------------------------------------------------
    screen(r"Let's choose where to install nixarchy")
    gum("choose")
    answer("\n")

    # ---- encrypt, then the summary -------------------------------------
    screen("Everything on /dev/vdc will be overwritten")
    gum("confirm")
    answer("\n")

    # The line gum confirm draws after the table, so waiting on it is waiting
    # for the whole summary. Not the rows themselves: wait_for_console_text
    # CONSUMES what it reads, and "Hostname" and "wizardbox" are on one row, so
    # matching the first swallowed the second and the wait never returned. The
    # rows are asserted from the full console log further down instead.
    screen("Does this look right")
    gum("confirm")
    answer("\n")

    screen("dry run: no disk touched")

    # ---- did it finish, and did it finish cleanly? ---------------------
    machine.wait_until_fails("systemctl is-active wizard")
    status = machine.succeed(
        "systemctl show -p ExecMainStatus --value wizard").strip()
    assert status == "0", f"the wizard exited {status}, not 0"

    # ---- the summary screen said what was typed ------------------------
    #
    # From the full console log rather than another wait: wait_for_console_text
    # consumes the queue it reads, so re-reading a line an earlier assertion
    # already matched is not possible. gum table's output is printed, not
    # driven, so every row of it is on this log. Named console_log because the driver
    # already has a `log`, which is its logger.
    console_log = machine.get_console_log()

    def row(setting, value):
        """gum table draws one row per setting; both halves have to be on it.

        Searched as a pair rather than separately because "true" and "wizard"
        appear elsewhere on a console this chatty, and a summary that showed
        the right words against the wrong settings is precisely the bug this
        screen exists to catch.
        """
        for line in console_log.splitlines():
            if setting in line and value in line:
                return
        raise AssertionError(f"the summary has no {setting} row reading {value}")

    row("Hostname", "wizardbox")
    row("Username", "wizard")
    row("Timezone", "Europe/London")
    row("Keyboard", "us")
    row("Disk", "/dev/vdc")
    row("Encrypted", "true")
    row("Password", "********")
    # The disks the size floor was supposed to hide. /dev/vda is this machine's
    # own root and /dev/vdb is a gigabyte; an installer offering either is the
    # bug ask_device's floor exists for.
    disk_screen = console_log[console_log.index("Let's choose where to install"):]
    for hidden in ["/dev/vda", "/dev/vdb"]:
        assert hidden not in disk_screen, (
            f"{hidden} is under the 8 GiB floor and was offered as an install target")

    # ---- the answers reached the flake ---------------------------------
    #
    # The point of the whole wizard: every answer ends up as text in the
    # generated flake. A screen that accepted a value and dropped it would
    # satisfy every assertion above.
    work = machine.succeed(
        "ls -d /tmp/tmp.*/ | while read -r d; do "
        "[ -f \"$d/flake.nix\" ] && echo \"$d\"; done | head -1").strip()
    assert work, "the dry run wrote no flake"
    print(machine.succeed(f"ls -a {work}"))

    # The machine is a directory named for the hostname answer (#123), so
    # finding it at all is the first assertion: flake.nix stays at the root
    # and enumerates ./hosts, and everything the wizard collected lands one
    # level down.
    host = f"{work}/hosts/wizardbox"
    machine.succeed(f"test -d {host}")

    flake = machine.succeed(f"cat {work}/flake.nix")
    default = machine.succeed(f"cat {host}/default.nix")
    configuration = machine.succeed(f"cat {host}/configuration.nix")
    for text, where, name in [
        ('hostname = "wizardbox"', default, "hostname"),
        ('username = "wizard"', default, "username"),
        ('device = "/dev/vdc"', default, "device"),
        ("encrypt = true", default, "encryption"),
        ('time.timeZone = "Europe/London"', configuration, "timezone"),
        ('console.keyMap = "us"', configuration, "keymap"),
    ]:
        assert text in where, f"the {name} answer never reached the flake"

    # And the root flake names no machine itself -- it reads ./hosts. A
    # hostname hardcoded back into it would still pass every assertion above.
    assert "wizardbox" not in flake, (
        "flake.nix names the machine; it is supposed to find machines by "
        "reading ./hosts, so that adding one is adding a directory")

    # A dry run must not have touched anything. The disk it was pointed at is
    # the one to look at: still unpartitioned, still empty.
    machine.fail("blkid /dev/vdc")
    print("the wizard asked six questions, rejected three bad answers, and "
          "wrote a flake carrying the rest")
  '';
}
