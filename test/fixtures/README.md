# Test fixtures

JSON bodies that tests load with `File('test/fixtures/<name>.json')`.

| File | Source |
| --- | --- |
| `mobile_goals.json`, `mobile_goal_detail.json` | Goals API (v1) responses. |
| `mobile_wallets.json` | Copied by hand from `docs/api-contract-v2.md` §2 (`GET /api/mobile/wallets`). |
| `categories.json` | Copied by hand from the backend `lib/categories.ts` list. |

`categories.json` and `mobile_wallets.json` are **pre-B6 fixtures**: they
were written before the backend serves these endpoints. Regenerate both from
real backend responses at B6 and update the tests that read them. Until
then, keep `mobile_wallets.json` in sync with contract §2 on `main`.
