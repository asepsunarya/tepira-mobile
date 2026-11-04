# Test fixtures

JSON bodies that tests load with `File('test/fixtures/<name>.json')`.

| File | Source |
| --- | --- |
| `mobile_goals.json`, `mobile_goal_detail.json` | Goals API (v1) responses. |
| `mobile_wallets.json` | Copied by hand from `docs/api-contract-v2.md` §2 (`GET /api/mobile/wallets`). |
| `categories.json` | Copied by hand from the backend `lib/categories.ts` list. |
| `mobile_today_budget.json`, `mobile_today_wallet.json` | `docs/api-contract-v2.md` §5 (`GET /api/mobile/today`), examples 1 and 2. |
| `mobile_expense_created.json`, `mobile_expense_deduped.json` | §6 (`POST /api/mobile/expenses`), examples 1 and 2. |
| `mobile_expenses.json` | §7 (`GET /api/mobile/expenses`), example 1. |
| `mobile_expense_updated.json` | §8 (`PATCH /api/mobile/expenses/{id}`), example 2 (two wallets). |
| `mobile_expense_deleted.json`, `mobile_expense_deleted_orphan.json` | §9 (`DELETE /api/mobile/expenses/{id}`), examples 1 and 2. |

The v2 fixtures are copied verbatim from the contract, which is generated
from the real handlers; `fixtures_contract_test.dart` fails when one drifts.

`categories.json` and `mobile_wallets.json` are **pre-B6 fixtures**: they
were written before the backend serves these endpoints. Regenerate both from
real backend responses at B6 and update the tests that read them. Until
then, keep `mobile_wallets.json` in sync with contract §2 on `main`.
