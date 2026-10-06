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
# #949: the menu named 14 ids and the script accepted 10, so
# four rows printed a usage line and exited 1 -- into a
# detached terminal nobody sees. The `blind` check above is
# correct and is one FIELD away from this: it reads `checked`,
# and the bug was in `action`.
#
# Parsed from the script rather than kept as a list here:
# a second copy is the defect one level up (AGENTS.md 4, a
# list naming things elsewhere wants a comparison).
script = open(sys.argv[2]).read()
accepted = set()
for arm in re.findall(r"^([a-z0-9| -]+)\)\s*agent=", script, re.M):
    for alt in arm.split("|"):
        accepted.add(alt.strip())
# A parse that matches nothing flags every row, which is loud.
# A parse that over-matches accepts everything and passes
# having checked nothing, which is a green light. So refuse an
# implausible count rather than report one, the way
# readme-counts.sh refuses at zero.
if len(accepted) < 10:
    sys.exit(
        "the accepted-agent parse found %d ids; the case arms in "
        "omarchy-default-agent must have moved. This check is "
        "refusing rather than passing." % len(accepted)
    )
unknown = sorted(
    k for k in agents
    if (d[k].get("action", "").split() + [""])[1] not in accepted
)
if unknown:
    sys.exit(
        "menu rows name agents omarchy-default-agent rejects: %s\n"
        "  it accepts: %s" % (unknown, sorted(accepted))
    )
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
