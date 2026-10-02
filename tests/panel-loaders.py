#!/usr/bin/env python3
"""Asserts shell.qml keeps a panel's Loader across a plugin change (#1155),
and that the #901 part-A fix (enabledPluginSignature) is still there.

Usage: panel-loaders.py <path-to-shell.qml>
Exits 0 if every check passes, 1 and a FAIL line per failure otherwise.
"""
import re
import sys


def main() -> int:
    path = sys.argv[1]
    text = open(path, encoding="utf-8").read()
    failures = []

    # 1. The Instantiator's model is the synced ListModel, not a fresh JS
    #    array handed to it on every plugin change.
    if not re.search(r"Instantiator\s*\{.*?model:\s*panelEntryModel", text, re.DOTALL):
        failures.append("Instantiator { ... model: panelEntryModel } not found")
    if "panelEntries" in text:
        failures.append(
            '"panelEntries" still present -- the plain JS array property was not replaced'
        )

    # 2. The keep-condition: an entry whose plugin still loads the same way
    #    is left alone rather than rebuilt.
    keep_cond = (
        "next.kind === row.entryKind && next.keepLoaded === row.keepLoaded "
        "&& next.sourceUrl === row.sourceUrl"
    )
    idx = text.find(keep_cond)
    if idx == -1:
        failures.append("keep-condition for an unchanged panel entry not found")
    elif "delete wanted[row.pluginId]" not in text[idx : idx + 400]:
        failures.append(
            "keep-condition found, but no 'delete wanted[row.pluginId]' follows it"
        )

    # 3. unloadPanels clears the model in place rather than reassigning it.
    m = re.search(r"function unloadPanels\(\)\s*\{(.*?)\n  \}", text, re.DOTALL)
    if not m:
        failures.append("function unloadPanels() {...} not found")
    elif "panelEntryModel.clear()" not in m.group(1):
        failures.append("unloadPanels() does not call panelEntryModel.clear()")

    # 4. Part A (#901) survived carrying #1155 on top of it.
    if "function enabledPluginSignature()" not in text:
        failures.append(
            "function enabledPluginSignature() missing -- #901 part A did not survive"
        )

    if failures:
        for f in failures:
            print(f"FAIL: {f}")
        return 1

    print("panel loaders: all four checks pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
