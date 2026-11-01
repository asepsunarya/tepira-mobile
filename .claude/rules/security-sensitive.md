---
description: Auth, API client, and storage code follows the security-and-hardening skill
paths:
  - "lib/features/auth/**"
  - "lib/**/*auth*"
  - "lib/data/**"
  - "lib/**/storage/**"
  - "android/app/src/main/AndroidManifest.xml"
  - "ios/Runner/Info.plist"
---

# Security-sensitive code

- Follow the `security-and-hardening` skill before changing anything here.
- Tokens and session cookies live only in `flutter_secure_storage`; never in `SharedPreferences`, logs, or source.
- Validate every API response at the boundary (DTO parsing with explicit null handling); never trust the shape.
- Pin the API base URL to HTTPS; no cleartext traffic in the Android manifest or iOS ATS exceptions.
- Never log or display secrets, tokens, or full PII; redact in error reports.
- Treat any change here as "ask first" (see Boundaries in `CLAUDE.md`) and as a `/ship` fan-out candidate.
- Pre-commit checklist: `.claude/references/security-checklist.md`.
