# Renders the report step's GitHub expressions into plain shell.
import pathlib
import re

pattern = re.compile(r"\$\{\{\s*(.*?)\s*\}\}")
source = pathlib.Path("step.sh").read_text()
fixed = {"github.server_url": "https://github.test", "github.repository": "o/r", "github.run_id": "123"}

def replace(match):
    expr = match.group(1)
    if expr == "contains(needs.*.result, " + chr(39) + "cancelled" + chr(39) + ")":
        return "true"
    if re.fullmatch(r"needs\.[A-Za-z0-9_-]+\.result", expr):
        return "cancelled" if expr == "needs.keyboard-boot.result" else "success"
    if expr in fixed:
        return fixed[expr]
    raise ValueError("unhandled GitHub expression: " + expr)

rendered = pattern.sub(replace, source)
if pattern.search(rendered):
    raise ValueError("unreplaced GitHub expression")
pathlib.Path("rendered.sh").write_text(rendered)
