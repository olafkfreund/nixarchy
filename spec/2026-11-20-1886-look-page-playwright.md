---
status: approved
issue: 1886
intent: intent/2026-11-20-1886-look-page-playwright.md
---

# Spec: `omarchy agent look page` works without mise

## Design

In `pkgs/omarchy/default.nix`, beside the other quattro-only patches
(`if [ -e $out/share/omarchy/bin/omarchy-agent-look-page ]`):

- replace upstream's mise block (kept verbatim in
  `pkgs/omarchy/look-page-playwright.upstream.sh`, so a changed upstream fails
  the build with `--replace-fail`) with `playwright=${playwright-driver}`;
- the script's `require` argument `"$playwright/node_modules/playwright"`
  becomes `"$playwright"`: nixpkgs' `playwright-driver` output *is* the
  `playwright-core` package, which exports `chromium` the same way;
- `mise exec node -- node -` becomes `${nodejs}/bin/node -`.

The browser stays upstream's choice: `google-chrome-stable` or `chromium` from
PATH, passed as `executablePath`, so Playwright's own browser downloads are not
needed. Drop the script's row from `data/mise-allow.nix`.

## Alternatives rejected

- Shipping mise for this one command: the port is mise-free by design.
- `playwright-driver.browsers`: hundreds of MB for a browser the user already has.

## Risks

A Playwright/Chromium version gap could break the CDP launch. Upstream already
drives whichever Chrome is installed, so the exposure is the same as on Arch.

## Verification

`checks.mise-free` fails with the row dropped and no patch (§1), passes with
both. One real run of the built script against a `file://` page on this host.
