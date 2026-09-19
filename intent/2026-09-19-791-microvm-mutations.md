---
status: approved
issue: 791
---

# Intent: Safe MicroVM mutations

Owner approved continued issue planning and implementation without further approval on 2026-09-19.

## Problem

VM mutations accept paths outside a VM and regex template names, and can race detached unit handoff. Protect existing state and refuse invalid inputs.
