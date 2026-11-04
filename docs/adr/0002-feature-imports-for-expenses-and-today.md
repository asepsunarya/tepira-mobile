# ADR 0002: Feature-to-feature imports for expenses, wallets and today

Status: accepted. Date: 2026-11-04.

## Context

CLAUDE.md says nothing in `features/a` imports from `features/b`. SPEC-v2 asks
for three links between features that this rule does not allow:

- §6 places the Jajan form (`features/expenses/expense_form.dart`) inside the
  Catat screen of `features/goals` (`contribute_screen.dart`), and the
  "Aman dipakai hari ini" card (`features/today`) on the Desa
  (`features/goals/goals_screen.dart`).
- §4 `expenses` requires each expense write to update `walletsProvider` and
  `todayProvider` from the answer's `wallet(s)` and `today`, without a GET.
  The writer in `features/expenses` therefore calls into
  `features/wallets` and `features/today`, and its models carry the
  `Wallet` and `TodaySummary` types.

Moving these widgets, providers and models into `core/` would put
feature-specific state and UI there and blur what `core/` means.

## Decision

Allow these imports as exceptions to the rule, in one direction each:

- `features/goals` → `features/expenses` (`expense_form.dart`) and
  `features/today` (`today_providers.dart`, `widgets/safe_today_card.dart`).
- `features/expenses` → `features/wallets` (`wallet_providers.dart`,
  `model/`) and `features/today` (`today_providers.dart`, `model/`).

`features/wallets` and `features/today` import no other feature. Any new
feature-to-feature import needs its own ADR or an amendment here.

## Consequences

- The code keeps the SPEC-v2 §6 structure; no shared layer is added.
- There are no import cycles: goals → expenses → wallets/today.
- Tests for the hosting screens override the hosted features' repositories.
