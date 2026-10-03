"""Run the QML's literal probe command against stable Linux process fixtures."""

import concurrent.futures
import contextlib
import json
import pathlib
import re
import select
import subprocess
import sys

if len(sys.argv) > 1 and sys.argv[1] == "--ancestor-probe":
    result = subprocess.run(
        json.loads(sys.argv[2]), capture_output=True, text=True, timeout=5, check=False
    )
    print(result.stdout, end="")
    sys.exit(result.returncode)


def probe_command(source):
    match = re.search(r"statusProc.command\s*=\s*\[(.*?)\];", source, re.DOTALL)
    assert match, "the indicator's probe command was not found"
    remaining = match[1].strip()
    decoder = json.JSONDecoder()
    command = []
    operator = ","
    while remaining:
        value, length = decoder.raw_decode(remaining)
        assert isinstance(value, str), "probe arguments must be literal strings"
        if operator == "+":
            command[-1] += value
        else:
            command.append(value)
        remaining = remaining[length:].strip()
        if remaining:
            operator, remaining = remaining[0], remaining[1:].strip()
            assert operator in (",", "+"), "unsupported probe expression"
            assert remaining, "unfinished probe argument"
    assert command[0] == "pgrep", command
    return command


@contextlib.contextmanager
def process(argv):
    # The holder accepts any argv and waits on stdin; no rebuild is executed.
    child = subprocess.Popen(
        argv,
        executable=holder,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True,
    )
    try:
        assert select.select([child.stdout], [], [], 5)[0], "fixture did not start"
        assert child.stdout.readline() == "ready\n"
        actual = pathlib.Path(f"/proc/{child.pid}/cmdline").read_bytes()
        assert actual == b"\0".join(arg.encode() for arg in argv) + b"\0"
        yield child
    finally:
        child.stdin.close()
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait(timeout=5)
        child.stdout.close()


def probe():
    result = subprocess.run(
        command, capture_output=True, text=True, timeout=5, check=False
    )
    assert result.returncode in (0, 1), result.stderr
    return result


def check(argv, expected):
    with process(argv) as child:
        result = probe()
        matched = str(child.pid) in result.stdout.splitlines()
        assert matched == expected, (
            f"{'missed rebuild' if expected else 'false rebuild'}: {argv!r}; "
            f"pgrep exit={result.returncode}, pids={result.stdout.strip()!r}"
        )


source = pathlib.Path(sys.argv[1]).read_text()
holder = str(pathlib.Path(sys.argv[2]).resolve())
command = probe_command(source)

# Keep exact peer-probe argv alive so overlap is guaranteed, not a timing race.
with contextlib.ExitStack() as peers:
    for _ in range(8):
        peers.enter_context(process(command))
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        results = list(executor.map(lambda _: probe(), range(8)))
    for result in results:
        assert result.returncode == 1, (
            "concurrent probe arguments reported a rebuild while idle: "
            f"pgrep exit={result.returncode}, pids={result.stdout.strip()!r}"
        )
print("PASS: eight concurrent probes ignore each other's command lines", flush=True)

# Give a real Python parent a rebuild argv[0], then run the probe inside it.
ancestor = subprocess.run(
    [
        "nixos-rebuild",
        str(pathlib.Path(__file__).resolve()),
        "--ancestor-probe",
        json.dumps(command),
    ],
    executable=sys.executable,
    capture_output=True,
    text=True,
    timeout=10,
    check=False,
)
assert ancestor.returncode == 1, f"ancestor reported a rebuild: {ancestor!r}"
print("PASS: the probe ignores a rebuild command in its ancestors", flush=True)

positive = [
    ["nixos-rebuild", "switch"],
    ["/nix/store/example/bin/nixos-rebuild-ng", "boot"],
    ["/nix/store/example/bin/.nixos-rebuild-wrapped", "test"],
    ["nixarchy-apply", "--detach", "--yes"],
    ["/nix/store/example/bin/.nixarchy-apply-wrapped", "--yes"],
    ["/nix/store/example/bin/switch-to-configuration", "switch"],
    ["/nix/store/example/bin/bash", "-e", "-u", "/tmp/nixarchy-apply"],
    ["sh", "/tmp/switch-to-configuration", "test"],
    ["python3.13", "-P", "/tmp/.nixos-rebuild-wrapped", "switch"],
    ["python", "/tmp/nixos-rebuild-ng", "build"],
    *[["nh", "os", action] for action in ("switch", "boot", "test", "build")],
    ["/nix/store/example/bin/.nh-wrapped", "os", "switch"],
]
negative = [
    ["emacs", "/tmp/nixos-rebuild.md"],
    ["bash", "-c", "echo nixarchy-apply"],
    ["python3", "review.py", "switch-to-configuration"],
    ["nh", "search", "hello"],
    ["nh", "home", "switch"],
    ["nixos-rebuild-notes"],
    ["nixarchy-apply-helper"],
]
for argv in positive:
    check(argv, True)
for argv in negative:
    check(argv, False)
print(f"PASS: {len(positive)} rebuild commands and {len(negative)} unrelated commands")
