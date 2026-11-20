# Playwright is a mise tool installed on first use, with Node before it.
playwright=$(mise where playwright 2>/dev/null)
if [[ ! -d $playwright/node_modules/playwright ]]; then
  mise install node playwright >/dev/null 2>&1
  playwright=$(mise where playwright 2>/dev/null)
fi
if [[ ! -d $playwright/node_modules/playwright ]]; then
  echo "Playwright isn't installed and couldn't be: run mise install node playwright" >&2
  exit 1
fi
