#!/usr/bin/env python3
# Each menu row's column 4/5 must say exactly what differs between the console
# table (what the installer reads the password under) and the XKB layout's
# first group (what the login screen reads it under). Why: tests/AGENTS.md.
# usage: keymaps-compare.py <menu> <libxkbcommon.so> <Compose>   (loadkeys, xkbcli on PATH)
import ctypes, re, subprocess, sys

menu, xkbso, compose = sys.argv[1:4]
# The password keys: digit row, three letter rows, and the ISO key beside Shift.
KEYS = [*range(2, 14), *range(16, 28), *range(30, 42), *range(43, 54), 86]
ACCENT = {0: "`", 1: "'", 2: "^", 3: "~", 4: '"', 5: ","}
X = ctypes.CDLL(xkbso)
X.xkb_keysym_from_name.argtypes = [ctypes.c_char_p, ctypes.c_int]
X.xkb_keysym_from_name.restype = ctypes.c_uint32
X.xkb_keysym_to_utf32.argtypes = [ctypes.c_uint32]
X.xkb_keysym_to_utf32.restype = ctypes.c_uint32

COMPOSE = {}
for line in open(compose, encoding="utf8", errors="replace"):
    m = re.match(r'\s*<(dead_\w+)>\s*<(\w+)>\s*:\s*"((?:[^"\\]|\\.)*)"', line)
    if m:
        COMPOSE[(m[1], m[2])] = m[3]


def console(name):
    out = subprocess.run(["loadkeys", "--unicode", "--mktable", name],
                         capture_output=True, text=True, check=True).stdout
    table = [[int(v, 16) for v in re.findall(r"0x[0-9a-f]+",
              re.search(rf"short {n}_map\[NR_KEYS\] = \{{(.*?)\}}", out, re.S)[1])]
             for n in ("plain", "shift")]
    accents = {}
    block = re.search(r"accent_table\[MAX_DIACR\] = \{(.*?)\n\};", out, re.S)
    for d, b, r in re.findall(r"\{'(\\.|.)', '(\\.|.)', (0x[0-9a-f]+)\}", block[1] if block else ""):
        # setdefault: the kernel takes the first match, and some maps list two.
        # [-1]: an escaped '\\' or '\'' is its last character; removing backslashes empties the first.
        accents.setdefault((d[-1], b[-1]), chr(int(r, 16)))
    return table, accents


def typed(code):
    kind = code >> 8
    if kind in (0xf0, 0xfb):
        return chr(code & 0xff) if (code & 0xff) >= 0x20 and code & 0xff != 0x7f else None
    return chr(code) if 0x20 <= code < 0xf000 else None


def xkb(spec):
    layout, _, variant = spec.split(",")[0].partition(":")
    out = subprocess.run(["xkbcli", "compile-keymap", "--layout", layout]
                         + (["--variant", variant] if variant else []),
                         capture_output=True, text=True, check=True).stdout
    codes = {a: int(b) for a, b in re.findall(r"<([A-Za-z0-9+_-]+)>\s*=\s*(\d+);", out)}
    syms = {}
    for name, body in re.findall(r"key <([A-Za-z0-9+_-]+)>\s*\{(.*?)\};", out, re.S):
        m = re.search(r"symbols\[1\]\s*=\s*\[([^\]]*)\]", body) or re.search(r"\[\s*([^\]]*)\]", body)
        if m and name in codes:
            syms[codes[name] - 8] = [s.strip() for s in m[1].split(",")]
    return syms


def char(sym):
    if sym is None or sym.startswith("dead_"):
        return None
    u = X.xkb_keysym_to_utf32(X.xkb_keysym_from_name(sym.encode(), 0))
    return chr(u) if u >= 0x20 else None


def level(syms, code, i):
    s = syms.get(code, [])
    return s[i] if i < len(s) else (s[0] if s else None)


def differs(console_map, spec):
    (table, accents), syms = console(console_map), xkb(spec)
    out = set()
    for code in KEYS:
        for i in (0, 1):
            value, sym = table[i][code], level(syms, code, i)
            ch = typed(value)
            if ch is not None and ch != char(sym):
                out.add(ch)
            if value >> 8 != 0xf4:
                continue
            accent = ACCENT.get(value & 0xff)
            if not (sym or "").startswith("dead_"):
                out.add(accent)  # no dead key there, so the accent itself moved
            for base in KEYS:
                for j in (0, 1):
                    b, bsym = typed(table[j][base]), level(syms, base, j)
                    done = accents.get((accent, b)) if b and b.isalpha() else None
                    if done and done != COMPOSE.get((sym, bsym)):
                        out.add(done)
    return out


failed = count = 0
for line in open(menu, encoding="utf8"):
    f = line.rstrip("\n").split("\t") + ["", ""]
    label, cmap, spec, chars, token = f[:5]
    count += 1
    want = differs(cmap, spec)
    if token == "dead":
        if all(c.isascii() for c in want):
            print(f"FAILED: {label}: dead token, and nothing non-ASCII differs"); failed += 1
        want = {c for c in want if c.isascii()}
    elif token:
        print(f"FAILED: {label}: unknown token {token}"); failed += 1
    have = set(chars)
    if have != want:
        print(f"FAILED: {label} ({cmap} -> {spec}): column 4 lacks {sorted(want - have)}, "
              f"and lists {sorted(have - want)} which do not differ"); failed += 1
if count == 0 or failed:
    sys.exit(1)
print(f"OK: {count} rows say exactly what differs")
