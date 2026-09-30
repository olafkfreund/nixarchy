---
status: draft
issue: 1087
author: olafkfreund
---

# Intent: Keep hypr-rdp credentials valid in rendered TOML

## Problem

`modules/services/hypr-rdp.nix` inserts the decrypted password directly between TOML double quotes in its sops template. The same template inserts `bind`, `username`, `output`, `certFile`, and `keyFile` without TOML escaping. A quote, backslash, or newline can make the generated file invalid or change the value the daemon reads. The runtime guard checks only that the username and password lines look nonempty; it does not validate TOML or confirm the parsed credential matches the secret. When parsing fails, hypr-rdp does not start.

The issue's unescaped interpolation claim holds. Its wording that **every** quote or backslash produces invalid TOML is too broad: a backslash followed by a valid TOML escape can parse, but the resulting credential differs from the literal secret. The issue also omits the certificate and key path fields, which use the same quoting pattern. The module and remote-desktop manual already warn users to avoid these password characters; that warning documents the defect rather than preventing it.

## Proposed outcome

The rendered configuration either preserves each permitted input exactly as hypr-rdp reads it, or refuses an unsupported value with a clear error before the daemon starts. A password never silently changes meaning because of TOML quoting. The startup refusal for missing or empty credentials remains effective.

## Affected users and systems

Users who enable `programs.nixarchy.services.hypr-rdp`, especially those choosing punctuation in an RDP password or configuring a nondefault username, bind address, output, or certificate path. The sops-rendered user service configuration and remote-desktop guidance are affected; other services are not.

## Constraints

- Keep the decrypted password in a runtime secret or rendered file, never in the Nix store, command line, journal, or repository.
- Preserve the existing fail-closed behavior for absent or empty credentials and the file's `0400` ownership and permissions.
- Cover all quoted fields, including `certFile` and `keyFile`, without changing unrelated option behavior.
- Any check must fail with the original defect restored and pass with the fix. Do not use a VM or the expensive `checks.options` locally.

## Open questions

1. **Resolved by the owner:** escape password backslashes and double quotes at runtime, where the rendered secret is read, using one `sed` expression. Reject control characters with a clear error. Prove both the rendered file and the TOML parser's value.
2. **Resolved by the owner:** escape nonsecret string fields at evaluation, preserving their option types and literal parsed values.
