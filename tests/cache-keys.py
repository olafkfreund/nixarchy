#!/usr/bin/env python3
"""Verify a narinfo's Sig against a Nix public key: cache-keys.py <narinfo> <full key>."""
import base64
import sys

from nacl.exceptions import BadSignatureError
from nacl.signing import VerifyKey

narinfo, key = sys.argv[1], sys.argv[2]
name, _, pub = key.partition(":")
fields, sigs = {}, []
for line in open(narinfo):
    k, _, v = line.rstrip("\n").partition(": ")
    if k == "Sig":
        sigs.append(v)
    else:
        fields[k] = v.strip()
refs = ",".join("/nix/store/" + r for r in fields.get("References", "").split())
fp = f"1;{fields['StorePath']};{fields['NarHash']};{fields['NarSize']};{refs}"
mine = [s.partition(":")[2] for s in sigs if s.partition(":")[0] == name]
if not mine:
    sys.exit(f"{narinfo}: no Sig for {name} (key {key})")
try:
    VerifyKey(base64.b64decode(pub)).verify(fp.encode(), base64.b64decode(mine[0]))
except BadSignatureError:
    sys.exit(f"{narinfo}: Sig does not verify with key {key}")
