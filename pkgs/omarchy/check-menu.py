import json, re, sys
t = open(sys.argv[1]).read()
t = re.sub(r"^\s*//.*$", "", t, flags=re.M)
# It is jsonc, not json: comments and a trailing comma on the last
# entry are both legal and both present upstream. Strip them rather
# than report the file as broken, which is what the first version of
# this check did -- to a file it had not touched.
t = re.sub(r",(\s*[}\]])", r"\1", t)
d = json.loads(t)
agents = [k for k in d if k.startswith("setup.default.agent.") and k.count(".") == 3]
blind = [k for k in agents if "command -v" not in d[k].get("checked", "")]
if blind:
    sys.exit("agent rows that tick without checking the command: " + repr(blind))
if "setup.default.agent.antigravity" not in agents:
    sys.exit("the antigravity row did not survive")
ask = [k for k in d if k.startswith("trigger.ask")]
if len(ask) < 10:
    sys.exit("the Ask rows did not survive: %d found" % len(ask))
if "setup.local-ai" not in d:
    sys.exit("the Local AI row did not survive")
for k in ask + ["setup.local-ai"]:
    a = d[k].get("action")
    if a and not a.startswith("omarchy-launch-floating-terminal"):
        sys.exit("row %s does not open a terminal: %r" % (k, a))
print("menu ok: %d agent rows, every one install-checked" % len(agents))
