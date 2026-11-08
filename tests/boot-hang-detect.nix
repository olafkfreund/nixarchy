{ pkgs, ... }:
# A frozen guest fails wait_for_multi_user fast, with register evidence (#1594).
# Why: tests/AGENTS.md#boot-hang-detect
pkgs.testers.runNixOSTest {
  name = "nixarchy-boot-hang-detect";
  nodes.frozen.virtualisation.memorySize = 1024;
  nodes.healthy.virtualisation.memorySize = 1024;
  testScript = builtins.readFile ./vm-cleanup.py + ''

    # Case A: stop the CPUs mid-boot; the silence detector must fire.
    frozen.start()
    frozen.send_monitor_command("stop")
    time.sleep(1)
    began = time.monotonic()
    raised = None
    try:
        wait_for_multi_user(frozen, timeout=120, silence=20, probe_timeout=5, poke_watch=2)
    except BootHang as e:
        raised = e
    elapsed = time.monotonic() - began
    assert raised is not None, "wait_for_multi_user returned on a stopped guest"
    assert "console silent" in str(raised), f"wrong reason: {raised}"
    assert "IP=" in raised.monitor_dump, f"no registers in dump: {raised.monitor_dump}"
    # A rejected command still writes its header, so assert on the replies.
    for text in ("dumping local APIC state for CPU", "ioapic0: ver=", "used_idx:",
                 "poke nmi:", "poke sendkey alt-sysrq-w:"):
        assert text in raised.monitor_dump, f"{text!r} not in dump: {raised.monitor_dump}"
    for text in ("unknown command:", "monitor command failed", "monitor replied:"):
        assert text not in raised.monitor_dump, f"{text!r} in dump: {raised.monitor_dump}"
    assert elapsed < 60, f"took {elapsed:.0f} s to notice"
    assert "Reached target Multi-User System" not in "\n".join(frozen.full_console_log), \
        "guest reached multi-user before the stop landed; case A proves nothing"
    assert frozen.process is not None
    frozen.process.kill()
    frozen.process.wait()

    # Case B: a fresh, healthy guest must pass the same helper.
    healthy.start()
    wait_for_multi_user(healthy)

    # Case C: both pokes reach a healthy guest and it says so on the console.
    poked = "\n".join(_poke(healthy, 15, threading.Event()))
    nmi_part, _, key_part = poked.partition("poke sendkey")
    assert "NMI received for unknown reason" in nmi_part, f"NMI poke unanswered: {poked}"
    assert "This sysrq operation is disabled" in key_part, f"sysrq poke unanswered: {poked}"
  '';
}
