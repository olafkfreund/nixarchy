---
status: approved
issue: 791
intent: intent/2026-09-19-791-microvm-mutations.md
---

# Spec: Safe MicroVM mutations

Owner approved continued issue planning and implementation without further approval on 2026-09-19.

## Design

Validate every VM name with the existing create grammar before path construction. Match template names literally. Share an acquire-lock-then-unit-state check across mutators; prebuilt launch only acquires its handoff lock, because it is the unit itself. Test actual packaged CLI with disposable state and deterministic flock/systemctl stubs. No VM boots or live state access.
