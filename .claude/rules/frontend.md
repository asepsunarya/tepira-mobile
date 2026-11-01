---
description: Flutter UI code follows the frontend-ui-engineering skill and accessibility checklist
paths:
  - "lib/features/**"
  - "lib/**/widgets/**"
  - "lib/**/screens/**"
  - "lib/app.dart"
---

# Flutter UI code

- Follow the `frontend-ui-engineering` skill: small widgets, clear state placement, responsive layout for small phones and tablets.
- Reuse the theme and primitives in `lib/core/` before adding new colours, text styles, or one-off widgets.
- Every interactive widget has a `Semantics` label or tooltip, a tap target of at least 48x48, and readable contrast in the dark theme.
- Prefer `const` constructors and avoid rebuilding whole screens; watch only the provider slice a widget needs.
- Verify on a real device or emulator when behaviour depends on runtime (keyboard, safe areas, orientation).
- Checklist: `.claude/references/accessibility-checklist.md`. Performance baseline: `.claude/references/performance-checklist.md`.
