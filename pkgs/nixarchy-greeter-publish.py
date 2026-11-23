"""Validate a user's theme inbox and atomically publish an SDDM generation."""

import os
import pwd
import re
import shutil
import stat
import subprocess
import sys
import time
import tomllib
from pathlib import Path


COLOR = re.compile(r"#[0-9a-fA-F]{6}")
GENERATION = re.compile(r"gen-[0-9]+")
ROOT = Path(os.environ.get("NIXARCHY_GREETER_DIR", "/var/lib/nixarchy-greeter"))
WRONG_OWNER = object()


def read_input(path, limit, uid):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
    except FileNotFoundError:
        return None
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
            raise ValueError(f"unsafe input: {path}")
        if info.st_uid != uid:
            return WRONG_OWNER
        data = stream.read(limit + 1)
        if len(data) > limit:
            raise ValueError(f"oversized input: {path}")
        return data


def publish(uid):
    inbox = ROOT / "inbox"
    out = ROOT / "out"
    for _ in range(3):
        ready = read_input(inbox / "ready", 65536, uid)
        colors = read_input(inbox / "colors.toml", 65536, uid)
        image = read_input(inbox / "background", 50 * 1024 * 1024, uid)
        observed_ready = ready
        if any(item is WRONG_OWNER for item in (ready, colors, image)):
            ready, colors, image = None, None, None

        parsed = tomllib.loads(colors.decode("utf-8")) if colors is not None else {}
        values = {}
        for source, target in (("background", "background"), ("foreground", "foreground"),
                               ("accent", "accent"), ("red", "failed")):
            value = parsed.get(source)
            if isinstance(value, str) and COLOR.fullmatch(value):
                values[target] = value

        name = f"gen-{time.time_ns()}"
        generation = out / name
        generation.mkdir(mode=0o755)
        generation.chmod(0o755)
        request = generation / "request"
        request.write_bytes(ready or b"")
        request.chmod(0o644)
        if image is not None:
            coder = None
            for magic, name_of_coder in ((b"\x89PNG\r\n\x1a\n", "png"), (b"\xff\xd8\xff", "jpeg"),
                                         (b"GIF87a", "gif"), (b"GIF89a", "gif"), (b"BM", "bmp")):
                if image.startswith(magic):
                    coder = name_of_coder
                    break
            if coder is None and image.startswith(b"RIFF") and image[8:12] == b"WEBP":
                coder = "webp"
            if coder is not None:
                picture = generation / ".background.tmp.png"
                try:
                    result = subprocess.run(
                        ["magick", "-limit", "memory", "256MiB", "-limit", "map", "512MiB",
                         "-limit", "disk", "256MiB", "-limit", "width", "16KP",
                         "-limit", "height", "16KP", "-limit", "time", "30",
                         f"{coder}:-[0]", "-auto-orient", "-resize", "3840x2160>", "-strip",
                         f"png:{picture}"],
                        input=image, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                        timeout=60, check=False,
                    )
                    decoded = result.returncode == 0 and picture.is_file()
                except subprocess.TimeoutExpired:
                    decoded = False
                if decoded:
                    picture.chmod(0o644)
                    picture.rename(generation / "background.png")
                    values["wallpaper"] = f"{name}/background.png"
                else:
                    picture.unlink(missing_ok=True)

        temporary = generation / ".theme.conf.tmp"
        with temporary.open("w", encoding="utf-8") as stream:
            stream.write("[General]\n")
            for key, value in values.items():
                stream.write(f'{key}="{value}"\n')
        temporary.chmod(0o644)
        temporary.rename(generation / "theme.conf")

        current = out / "current"
        try:
            previous = os.readlink(current)
        except FileNotFoundError:
            previous = None
        for old in out.iterdir():
            if GENERATION.fullmatch(old.name) and old.name not in (name, previous):
                shutil.rmtree(old)
        pending = out / ".current-new"
        pending.unlink(missing_ok=True)
        pending.symlink_to(name)
        os.replace(pending, current)
        try:
            latest = read_input(inbox / "ready", 65536, uid)
        except (OSError, ValueError):
            return
        if latest == observed_ready:
            return


def main():
    try:
        uid = int(os.environ["NIXARCHY_GREETER_UID"]) if "NIXARCHY_GREETER_UID" in os.environ else pwd.getpwnam(os.environ["NIXARCHY_GREETER_USER"]).pw_uid
        publish(uid)
    except (OSError, ValueError, UnicodeError, tomllib.TOMLDecodeError, KeyError) as error:
        print(f"nixarchy-greeter-publish: {error}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
