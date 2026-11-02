# tepira `/api/mobile/*` v2: API contract (backend is the source of truth)

Generated 2026-11-02 from the **real route handlers** on tepira `main` at
`f74d790` (`app/api/mobile/**/route.ts`, after #33, #35 and #36). The handlers
run in Node through tepira's own handler-test harness (`test/harness/`: fake
Prisma, stub `@/lib/auth`, stub `next/cache`) with the fixed clock
`2026-11-01T07:00:00.000Z` (= 1 Nov 2026, 14:00 WIB) and fictional data. Every
JSON body below is verbatim handler output; only the session `token` is
shortened. Generator: `docs/contract-gen/` (see its README).

Where this file and `SPEC-v2.md` §3 disagree, this file wins and the SPEC is
corrected (SPEC-v2 §3, first paragraph).

v1 endpoints (`GET /api/mobile/goals`, `GET /api/mobile/goals/{id}`,
`POST /api/mobile/goals`) keep the v1 contract (`handoff/api-contract.md`) except
for the write guard and the 413 limit (§10). `POST /api/mobile/session` is
repeated in full in §1 because its error order changed.

## Fictional data used

Signed-in user `user_owner` (the configured owner, `TEPIRA_DEFAULT_USER_EMAIL`).
`AUTH_URL` = `https://tepira.example.test`.

| Table | Rows |
|---|---|
| Wallets | 3 `BCA` bank 8.250.000; 7 `Tabungan Kurban` bank, reserved, 3.000.000; 9 `Kartu Kredit` credit (debt) 1.200.000; 11 `Tunai` cash 20.000; 40 belongs to another user |
| Expenses | 480: 120.000 BCA, 30 Oct (October); 497: 15.000, wallet deleted (orphan), legacy category key `transport`, `source` null, dated `2026-10-31T23:40Z` = 1 Nov 06:40 WIB; 498: 10.000 Kartu Kredit today; 499: 25.000 BCA today |
| Salary Nov 2026 | allocations totalling 4.500.000 |
| Contributions | 500.000 on 1 Nov to goal 12 |

Wallet balances are stored **after** the expenses above already moved them.

## Common rules

- Base: same host as the web app (production `https://tepira.asepsunarya.com`).
- Every response (success and error) is JSON with these headers:
  `Content-Type: application/json`, `Cache-Control: no-store, max-age=0, private`,
  `Vary: Cookie`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`.
  `Retry-After` (seconds) is added on every `429` and on a retryable `500` (§6).
- **Envelope.** Success `{"ok": true, ...}`; error
  `{"ok": false, "error": "<code>", "message": "<Indonesian text, show as is>"}`.
  Branch on HTTP status + `error`, never on `message`.
- **Auth.** The Auth.js session cookie from §1 (`__Secure-authjs.session-token`
  in production). Every route below except §1 needs it.
- **camelCase**; money = integer rupiah; ids = integers (user `id` = string).
- **Time.** Instants (`asOf`, `date` of an expense, `createdAt`, `expiresAt`) =
  ISO-8601 UTC with millis. Calendar fields (`today.date`) = `YYYY-MM-DD` in WIB.
  **Months and days are WIB** (UTC+7, no DST) on every v2 endpoint.
- **Nullable fields are never missing** (e.g. `description`, `category`,
  `note`, `walletId`, `walletName`, `placeName`, `budget.limit`).
- **Request bodies.** `Content-Type: application/json` (`; charset=…` allowed),
  at most 64 KB (65.536 bytes), must be a JSON object; unknown keys are ignored.
  Body that does not parse as JSON → `400` "Isi permintaan harus berupa objek JSON.".
- **Path ids** (`{id}`) that are not a positive int32 (`abc`, `0`, `2147483648`)
  → `404 not_found`, same as a row that does not exist or belongs to another user.
- **Categories** in responses are always the label (legacy keys such as
  `transport` are mapped to `Transport`); every "no category" form → `null`.
  Requests must send the label.

### Error codes

| Status | `error` | Where |
|---|---|---|
| 400 | `bad_request` | validation; message names the field |
| 400 | `wallet_not_found` | expenses POST/PATCH: `walletId` not the user's |
| 401 | `unauthorized` | no/expired session |
| 401 | `invalid_token` | session: bad Google ID token |
| 403 | `forbidden_origin` | every state-changing route: request from another site |
| 403 | `not_allowed`, `account_not_linked` | session |
| 404 | `not_found` | missing/foreign row, bad path id, session disabled |
| 413 | `payload_too_large` | body > 64 KB on any route that reads a body |
| 415 | `unsupported_media_type` | body route without `application/json` |
| 429 | `rate_limited` | limits below; `Retry-After` header |
| 500 | `server_error` | anything else; `Retry-After: 1` when retryable (§6) |

### Write guard, read guard and rate limits

All in `lib/mobile/http.ts`.

| Route | Guard | Order of checks before the handler's own work |
|---|---|---|
| `POST /api/mobile/session` | `guardOrigin` + per-IP limit | 404 (disabled) → 403 Origin → 429 (10/min per IP) → 415/413 → 400/401/403 |
| `POST /api/mobile/wallets`, `PATCH /api/mobile/wallets/{id}`, `POST /api/mobile/goals`, `POST /api/mobile/expenses`, `PATCH /api/mobile/expenses/{id}`, `DELETE /api/mobile/expenses/{id}` | `guardWrite` | 403 Origin → 401 → 429 (30/min per user) → 404 bad path id → 415/413 → … |
| `GET /api/mobile/expenses` | `guardRead` | 401 → 429 (60/min per user) → 400 query → … |
| `GET /api/mobile/wallets`, `/today`, `/goals`, `/goals/{id}` | session check only | 401 → … (no Origin check, no limit) |

- **Origin check** (`isForeignOrigin`). Rejected with
  `403` → `{"ok":false,"error":"forbidden_origin","message":"Permintaan dari situs lain tidak diizinkan."}` when
  `Sec-Fetch-Site` is `cross-site` or `same-site` (with or without `Origin`), or an
  `Origin` header is present and is not exactly the origin of `AUTH_URL`
  (`NEXTAUTH_URL` when `AUTH_URL` is blank; any `Origin` is rejected when both are
  unset). **The native app sends neither header and always passes.** Do not add an
  `Origin` header in the app.
- **Write limit**: 30 a minute per user, one bucket shared by every `guardWrite`
  route. Every request that passes the Origin and session checks takes a token,
  including those then answered `400`, `404`, `413` or `415`; `401` and `403` do not.
  Over the limit: `429` → `{"ok":false,"error":"rate_limited","message":"Terlalu banyak permintaan. Coba lagi sebentar lagi."}`
  with `Retry-After: 2`.
- **Read limit**: 60 a minute per user on `GET /api/mobile/expenses` only, checked
  before the query is parsed (a `400` counts). Over the limit:
  `429` → `{"ok":false,"error":"rate_limited","message":"Terlalu banyak permintaan. Coba lagi sebentar lagi."}` with
  `Retry-After: 1`.
- **Sign-in limit**: 10 attempts a minute per client IP, successful or not, keyed
  on `X-Real-IP` (set by nginx); `X-Forwarded-For` is ignored.
- Limits are per server instance, best effort. The fixed test clock means the
  `Retry-After` values shown are for an empty bucket refilling (30/min → 2 s,
  60/min → 1 s, 10/min → 6 s).
- A static scan in tepira's tests (`test/harness/route-scan.mjs`,
  `test/mobile-api/b4-4-guards.test.mjs`) fails the build when any exported
  `POST`/`PUT`/`PATCH`/`DELETE` handler under `app/api/mobile/` does not call
  `guardWrite` or `guardOrigin` before any other call (only `parseClientIds` and
  `notFound` may come first, for the disabled-session check), or is exported in a
  form the scan cannot read.

## 1. `POST /api/mobile/session`

Exchanges a Google ID token for the Auth.js session token. No session needed.

- Enabled only when env `TEPIRA_MOBILE_GOOGLE_CLIENT_IDS` (comma-separated Google
  OAuth client IDs accepted as `aud`) is set; otherwise every request gets
  `404` → `{"ok":false,"error":"not_found","message":"Data tidak ditemukan."}` before any other check.
- Body `{"idToken": "<Google ID token>"}` (string, 1–4096 chars).
- **Email normalization.** The Google email is trimmed and lowercased. A first
  sign-in looks the user up by that email case-insensitively (with an exact
  re-check after normalizing the stored email, so `_`/`%` never act as wildcards)
  and a new `User` is stored with the normalized email. An existing user with
  the same email in any letter case but no linked Google account is refused with
  `account_not_linked`; a second account that differs only in case is never created.

Request with a token for a new Google account whose email is
`"  Rina.Baru@Example.TEST "` → **200** (new `User` + `Account` created):
```json
{
  "ok": true,
  "token": "eyJhbGciOiJkaXIiLCJlbmMiOiJBMjU2Q0JDLUhT…(Auth.js JWE, ~520 chars)",
  "expiresAt": "2026-12-01T07:00:00.000Z",
  "user": {
    "id": "user_004",
    "name": "Rina Baru",
    "email": "rina.baru@example.test",
    "image": "https://example.test/avatar/rina.png"
  }
}
```

Request with a token whose `sub` is already linked to `user_rina` → **200**:
```json
{
  "ok": true,
  "token": "eyJhbGciOiJkaXIiLCJlbmMiOiJBMjU2Q0JDLUhT…(Auth.js JWE, ~520 chars)",
  "expiresAt": "2026-12-01T07:00:00.000Z",
  "user": {
    "id": "user_rina",
    "name": "Rina Contoh",
    "email": "rina@example.test",
    "image": "https://example.test/avatar/rina.png"
  }
}
```

- `expiresAt` = now + 30 days. `user` has exactly `id`, `name`, `email`, `image`.
- Send the token back as the session cookie: `Cookie: __Secure-authjs.session-token=<token>`
  when `AUTH_URL` is https (production), `authjs.session-token=<token>` when it is http.
  A wrong cookie name means signed out (401). Sign-out = delete the token on the
  device; it stays valid until `expiresAt`, and stops working as soon as the email
  leaves the allowlist.

**Errors**, in the order they are checked:
- `404` → `{"ok":false,"error":"not_found","message":"Data tidak ditemukan."}`: `TEPIRA_MOBILE_GOOGLE_CLIENT_IDS` unset
- `403` → `{"ok":false,"error":"forbidden_origin","message":"Permintaan dari situs lain tidak diizinkan."}`: `Origin`/`Sec-Fetch-Site` from another site
- `429` → `{"ok":false,"error":"rate_limited","message":"Terlalu banyak percobaan masuk. Coba lagi sebentar lagi."}`:
  11th attempt from one IP within a minute; `Retry-After: 6`
- `415` → `{"ok":false,"error":"unsupported_media_type","message":"Format permintaan harus JSON."}`: Content-Type not JSON
- `413` → `{"ok":false,"error":"payload_too_large","message":"Isi permintaan terlalu besar."}`: body over 64 KB
- `400` → `{"ok":false,"error":"bad_request","message":"Permintaan tidak valid: idToken wajib diisi."}`: `idToken` missing, not a string, empty or over 4096 chars; body not JSON
- `401` → `{"ok":false,"error":"invalid_token","message":"Token Google tidak valid atau sudah kedaluwarsa. Coba masuk lagi."}`: bad signature, audience, issuer or expired
- `403` → `{"ok":false,"error":"not_allowed","message":"Akun ini belum terdaftar di tepira.id."}`: email not on the allowlist or not verified by Google
- `403` → `{"ok":false,"error":"account_not_linked","message":"Email ini sudah terdaftar dengan akun lain. Masuk lewat web tepira.id dulu."}`:
  an unlinked user already has this email (example: stored `Budi@Example.test`,
  token email `budi@example.test`)
- `500 server_error`: Google certificates unreachable, `AUTH_SECRET` missing.

## 2. `GET /api/mobile/wallets`

Order `sortOrder asc, createdAt asc` (same as the web). The client groups by flags.

**200**
```json
{
  "ok": true,
  "asOf": "2026-11-01T07:00:00.000Z",
  "period": {
    "year": 2026,
    "month": 11
  },
  "wallets": [
    {
      "id": 3,
      "name": "BCA",
      "type": "bank",
      "balance": 8250000,
      "displayBalance": 8250000,
      "isDebt": false,
      "isReserved": false,
      "description": null,
      "sortOrder": 0,
      "spentThisMonth": 25000
    },
    {
      "id": 7,
      "name": "Tabungan Kurban",
      "type": "bank",
      "balance": 3000000,
      "displayBalance": 3000000,
      "isDebt": false,
      "isReserved": true,
      "description": "Kurban 2027",
      "sortOrder": 1,
      "spentThisMonth": 0
    },
    {
      "id": 9,
      "name": "Kartu Kredit",
      "type": "credit",
      "balance": 1200000,
      "displayBalance": -1200000,
      "isDebt": true,
      "isReserved": false,
      "description": null,
      "sortOrder": 2,
      "spentThisMonth": 10000
    },
    {
      "id": 11,
      "name": "Tunai",
      "type": "cash",
      "balance": 20000,
      "displayBalance": 20000,
      "isDebt": false,
      "isReserved": false,
      "description": null,
      "sortOrder": 3,
      "spentThisMonth": 0
    }
  ],
  "totals": {
    "assets": 11270000,
    "debts": 1200000,
    "reserved": 3000000,
    "netWorth": 10070000,
    "free": 7070000
  }
}
```

- `balance` = raw DB value. For debt wallets it is the amount owed; for asset
  wallets it may be **negative** (overdraft, §12). `displayBalance` = what to show:
  debt always negative (`-abs(balance)`), assets = `balance` (negative included).
- `totals` = `summarizeWallets` over all the user's wallets:
  `assets` = sum of non-debt balances (reserved and negative included),
  `debts` = sum of `abs(balance)` of debt wallets, `reserved` = sum of reserved
  wallets, `netWorth = assets − debts`, `free = assets − debts − reserved`.
- `spentThisMonth` = sum of this wallet's expenses dated in the current WIB month.
- Errors: `401` → `{"ok":false,"error":"unauthorized","message":"Sesi sudah berakhir. Silakan masuk lagi."}`; `500 server_error`.

## 3. `POST /api/mobile/wallets`

Body: `name` string 1–60 chars, trimmed, no control chars (**required**);
`type` one of `bank`, `e-wallet`, `cash`, `investment`, `credit`, `paylater`,
`other` (**required**); `balance` integer −2147483648..2147483647, default `0`
(for debt = amount owed, must be ≥ 0); `isDebt` boolean, default `false`, forced
`true` for `credit`/`paylater`; `isReserved` boolean, default `false`;
`description` string ≤ 200 chars (`""`/`null` → `null`). `sortOrder` is not
accepted (server sets max + 1).

Request `{"name": "Dana Darurat", "type": "bank", "balance": 2000000, "isReserved": true, "description": "Jangan dipakai"}` → **201**
```json
{
  "ok": true,
  "wallet": {
    "id": 41,
    "name": "Dana Darurat",
    "type": "bank",
    "balance": 2000000,
    "displayBalance": 2000000,
    "isDebt": false,
    "isReserved": true,
    "description": "Jangan dipakai",
    "sortOrder": 4,
    "spentThisMonth": 0
  },
  "totals": {
    "assets": 13270000,
    "debts": 1200000,
    "reserved": 5000000,
    "netWorth": 12070000,
    "free": 7070000
  }
}
```

Request `{"name": "Paylater", "type": "paylater", "balance": 350000}` → **201** (`isDebt` forced):
```json
{
  "ok": true,
  "wallet": {
    "id": 42,
    "name": "Paylater",
    "type": "paylater",
    "balance": 350000,
    "displayBalance": -350000,
    "isDebt": true,
    "isReserved": false,
    "description": null,
    "sortOrder": 5,
    "spentThisMonth": 0
  },
  "totals": {
    "assets": 13270000,
    "debts": 1550000,
    "reserved": 5000000,
    "netWorth": 11720000,
    "free": 6720000
  }
}
```

(Ids come from the fake; production uses the DB sequence.)

**Errors**
- `403` → `{"ok":false,"error":"forbidden_origin","message":"Permintaan dari situs lain tidak diizinkan."}`
- `401` → `{"ok":false,"error":"unauthorized","message":"Sesi sudah berakhir. Silakan masuk lagi."}`
- `429 rate_limited` (write limit)
- `415` → `{"ok":false,"error":"unsupported_media_type","message":"Format permintaan harus JSON."}`
- `413` → `{"ok":false,"error":"payload_too_large","message":"Isi permintaan terlalu besar."}`
- `400` → `{"ok":false,"error":"bad_request","message":"Nama dompet harus diisi, maksimal 60 karakter."}`
- `400` → `{"ok":false,"error":"bad_request","message":"Jenis dompet tidak dikenal."}`
- `400` → `{"ok":false,"error":"bad_request","message":"Saldo harus berupa angka bulat."}`
- `400` → `{"ok":false,"error":"bad_request","message":"Jumlah terutang tidak boleh negatif."}`
- `400` → `{"ok":false,"error":"bad_request","message":"Jenis utang harus ya atau tidak."}`
- `400` → `{"ok":false,"error":"bad_request","message":"Dana dicadangkan harus ya atau tidak."}`
- `400` → `{"ok":false,"error":"bad_request","message":"Dompet tidak bisa sekaligus utang dan dana dicadangkan."}`
- `400` → `{"ok":false,"error":"bad_request","message":"Deskripsi maksimal 200 karakter."}`
- `400` → `{"ok":false,"error":"bad_request","message":"Isi permintaan harus berupa objek JSON."}`: body not an object (e.g. `[1,2]`) or not JSON
- `500 server_error`

## 4. `PATCH /api/mobile/wallets/{id}`

Partial body. Field left out = unchanged and not written; `null` clears only
`description` (`null` elsewhere = that field's 400). Each sent field uses the
§3 rule. Debt ↔ asset is locked (`isDebt` must equal the stored value, `type`
cannot become `credit`/`paylater` on an asset wallet); debt cannot be reserved.
"Owed must not be negative" is only checked when `balance` is sent, so a debt
wallet the web stored negative can still be renamed. Sending `balance` is a manual
correction and creates no expense.

Request `PATCH /api/mobile/wallets/3` `{"name": "BCA Utama", "description": null}` → **200**
```json
{
  "ok": true,
  "wallet": {
    "id": 3,
    "name": "BCA Utama",
    "type": "bank",
    "balance": 8250000,
    "displayBalance": 8250000,
    "isDebt": false,
    "isReserved": false,
    "description": null,
    "sortOrder": 0,
    "spentThisMonth": 25000
  },
  "totals": {
    "assets": 11270000,
    "debts": 1200000,
    "reserved": 3000000,
    "netWorth": 10070000,
    "free": 7070000
  }
}
```

**Errors**, in order: `403`, `401`, `429` (guard) → `404` → `{"ok":false,"error":"not_found","message":"Data tidak ditemukan."}` (bad
path id) → `415`/`413` → `404` (missing or another user's wallet, checked
**before** the body is validated) → `400`:
- `400` → `{"ok":false,"error":"bad_request","message":"Tidak ada perubahan."}`: no known field, or nothing to write
  (e.g. only `isDebt` equal to the stored value)
- `400` → `{"ok":false,"error":"bad_request","message":"Jenis utang tidak bisa diubah setelah dompet dibuat."}`: `isDebt` differs, or `type`
  `credit`/`paylater` on an asset wallet
- `400` → `{"ok":false,"error":"bad_request","message":"Dompet tidak bisa sekaligus utang dan dana dicadangkan."}`: `isReserved: true` on a debt wallet
- `400` → `{"ok":false,"error":"bad_request","message":"Nama dompet harus diisi, maksimal 60 karakter."}`: e.g. `{"name": null}`
- every §3 field message
- `404` also when a concurrent web edit flipped the debt group or deleted the wallet
  between read and write
- `500 server_error`

## 5. `GET /api/mobile/today`

Summary for the Desa screen, computed on request. No query parameters.

**200**, budget basis (salary allocations exist for the month). Today's expenses:
25.000 (BCA), 10.000 (Kartu Kredit), 15.000 (orphan row dated 06:40 WIB):
```json
{
  "ok": true,
  "asOf": "2026-11-01T07:00:00.000Z",
  "date": "2026-11-01",
  "period": {
    "year": 2026,
    "month": 11,
    "daysInMonth": 30,
    "daysLeft": 30
  },
  "spent": {
    "today": 50000,
    "month": 50000
  },
  "savedThisMonth": 500000,
  "budget": {
    "status": "WITHIN_BUDGET",
    "limit": 4500000,
    "spent": 50000,
    "remaining": 4450000
  },
  "safeToday": {
    "basis": "budget",
    "state": "ok",
    "days": 30,
    "allowance": 150000,
    "spentToday": 50000,
    "remaining": 100000
  },
  "wallets": {
    "free": 7070000,
    "reserved": 3000000
  }
}
```

**200**, wallet basis (same data, no salary/bonus allocation this month):
```json
{
  "ok": true,
  "asOf": "2026-11-01T07:00:00.000Z",
  "date": "2026-11-01",
  "period": {
    "year": 2026,
    "month": 11,
    "daysInMonth": 30,
    "daysLeft": 30
  },
  "spent": {
    "today": 50000,
    "month": 50000
  },
  "savedThisMonth": 500000,
  "budget": {
    "status": "NO_BUDGET",
    "limit": null,
    "spent": 50000,
    "remaining": null
  },
  "safeToday": {
    "basis": "wallet",
    "state": "ok",
    "days": 30,
    "allowance": 236833,
    "spentToday": 35000,
    "remaining": 201833
  },
  "wallets": {
    "free": 7070000,
    "reserved": 3000000
  }
}
```

`spent.today` counts every expense (50.000); `safeToday.spentToday` on the wallet
basis counts only those paid from an existing, non-reserved wallet (35.000: the
orphan row is left out). `allowance = floor((free + E_today' + E_next') / 30)`
= `floor((7.070.000 + 35.000) / 30)` = 236.833.

**200**, wallet basis after a 25.000 expense from `Tunai` (balance 20.000 → −5.000,
overdraft allowed): `free` drops by 25.000 and the negative balance is counted as
is; `allowance` is unchanged because today's spending is added back:
```json
{
  "ok": true,
  "asOf": "2026-11-01T07:00:00.000Z",
  "date": "2026-11-01",
  "period": {
    "year": 2026,
    "month": 11,
    "daysInMonth": 30,
    "daysLeft": 30
  },
  "spent": {
    "today": 75000,
    "month": 75000
  },
  "savedThisMonth": 500000,
  "budget": {
    "status": "NO_BUDGET",
    "limit": null,
    "spent": 75000,
    "remaining": null
  },
  "safeToday": {
    "basis": "wallet",
    "state": "ok",
    "days": 30,
    "allowance": 236833,
    "spentToday": 60000,
    "remaining": 176833
  },
  "wallets": {
    "free": 7045000,
    "reserved": 3000000
  }
}
```

- Fields: `date` = today in WIB; `period.daysLeft` = days to month end, today
  included; `spent.month` = `budget.spent` = all expenses dated in the WIB month;
  `savedThisMonth` = contributions dated in the WIB month (deposits only);
  `budget.status` `NO_BUDGET` | `WITHIN_BUDGET` | `OVER_BUDGET` (`limit` and
  `remaining` `null` for `NO_BUDGET`); `safeToday.basis` `budget` | `wallet`;
  `safeToday.state` `ok` | `over_today` | `over_month`; `remaining` may be
  negative; `wallets.free`/`reserved` = §2 `totals`.
- Formula: SPEC-v2 §3.4 (examples A–H are tests in tepira
  `lib/mobile/today.test.mjs`). The client shows these numbers; it does not
  recompute them.
- **Expense read range:** the route reads expenses dated from the start of the WIB
  month with **no upper bound**, so an expense dated tomorrow or later (which
  already moved its wallet) is added back on the wallet basis (`E_next'`); only
  rows dated inside the month feed `budget`.
- Errors: `401` → `{"ok":false,"error":"unauthorized","message":"Sesi sudah berakhir. Silakan masuk lagi."}`; `500 server_error`.

## 6. `POST /api/mobile/expenses`

Body: `amount` integer 1..100.000.000 (**required**, JSON number);
`walletId` positive int32 (**required**; the server never picks a wallet);
`category` label or `null`/`""`; `note` string ≤ 120 chars (`""`, whitespace or
`null` → `null`); `source` `"gaji"` | `"bonus"`, default `"gaji"`;
`date` `"YYYY-MM-DD"`, from 7 WIB days back to tomorrow. Leave `date` out (or
`null`/`""`) for "now": **the app must not send today's date** (a resend after
midnight WIB would then be "yesterday" and escape the dedupe). Another day is
stored at 12:00 WIB of that day.

Advisory lock per user (shared with Cyrene), wallet lookup, dedupe and insert run
in one transaction. The same body again within 120 s (from the app or from
Cyrene) returns the first row with `deduped: true` and **200**, without writing.

Request `{"amount": 18000, "walletId": 3, "category": "Makan harian", "note": "bakso"}` → **201**
```json
{
  "ok": true,
  "deduped": false,
  "expense": {
    "id": 500,
    "amount": 18000,
    "category": "Makan harian",
    "note": "bakso",
    "source": "gaji",
    "date": "2026-11-01T07:00:00.000Z",
    "createdAt": "2026-11-01T07:00:00.000Z",
    "walletId": 3,
    "walletName": "BCA",
    "placeName": null
  },
  "wallet": {
    "id": 3,
    "name": "BCA",
    "type": "bank",
    "balance": 8232000,
    "displayBalance": 8232000,
    "isDebt": false,
    "isReserved": false,
    "description": null,
    "sortOrder": 0,
    "spentThisMonth": 43000
  },
  "today": {
    "date": "2026-11-01",
    "period": {
      "year": 2026,
      "month": 11,
      "daysInMonth": 30,
      "daysLeft": 30
    },
    "spent": {
      "today": 68000,
      "month": 68000
    },
    "savedThisMonth": 500000,
    "budget": {
      "status": "WITHIN_BUDGET",
      "limit": 4500000,
      "spent": 68000,
      "remaining": 4432000
    },
    "safeToday": {
      "basis": "budget",
      "state": "ok",
      "days": 30,
      "allowance": 150000,
      "spentToday": 68000,
      "remaining": 82000
    },
    "wallets": {
      "free": 7052000,
      "reserved": 3000000
    }
  }
}
```

Same request again → **200**, `deduped: true`, same `expense.id`, nothing written:
```json
{
  "ok": true,
  "deduped": true,
  "expense": {
    "id": 500,
    "amount": 18000,
    "category": "Makan harian",
    "note": "bakso",
    "source": "gaji",
    "date": "2026-11-01T07:00:00.000Z",
    "createdAt": "2026-11-01T07:00:00.000Z",
    "walletId": 3,
    "walletName": "BCA",
    "placeName": null
  },
  "wallet": {
    "id": 3,
    "name": "BCA",
    "type": "bank",
    "balance": 8232000,
    "displayBalance": 8232000,
    "isDebt": false,
    "isReserved": false,
    "description": null,
    "sortOrder": 0,
    "spentThisMonth": 43000
  },
  "today": {
    "date": "2026-11-01",
    "period": {
      "year": 2026,
      "month": 11,
      "daysInMonth": 30,
      "daysLeft": 30
    },
    "spent": {
      "today": 68000,
      "month": 68000
    },
    "savedThisMonth": 500000,
    "budget": {
      "status": "WITHIN_BUDGET",
      "limit": 4500000,
      "spent": 68000,
      "remaining": 4432000
    },
    "safeToday": {
      "basis": "budget",
      "state": "ok",
      "days": 30,
      "allowance": 150000,
      "spentToday": 68000,
      "remaining": 82000
    },
    "wallets": {
      "free": 7052000,
      "reserved": 3000000
    }
  }
}
```

Request `{"amount": 40000, "walletId": 9, "category": null, "source": "bonus", "date": "2026-10-31"}`
→ **201**; the debt wallet's balance goes **up** (more owed), the row is dated
12:00 WIB on 31 Oct, so it is outside November's `spentThisMonth`
(`today` omitted):

```json
{
  "deduped": false,
  "expense": {
    "id": 501,
    "amount": 40000,
    "category": null,
    "note": null,
    "source": "bonus",
    "date": "2026-10-31T05:00:00.000Z",
    "createdAt": "2026-11-01T07:00:00.000Z",
    "walletId": 9,
    "walletName": "Kartu Kredit",
    "placeName": null
  },
  "wallet": {
    "id": 9,
    "name": "Kartu Kredit",
    "type": "credit",
    "balance": 1240000,
    "displayBalance": -1240000,
    "isDebt": true,
    "isReserved": false,
    "description": null,
    "sortOrder": 2,
    "spentThisMonth": 10000
  }
}
```

Request `{"amount": 25000, "walletId": 11}` on `Tunai` (balance 20.000) → **201**,
**overdraft allowed**, no balance check (`today` omitted):
```json
{
  "deduped": false,
  "expense": {
    "id": 502,
    "amount": 25000,
    "category": null,
    "note": null,
    "source": "gaji",
    "date": "2026-11-01T07:00:00.000Z",
    "createdAt": "2026-11-01T07:00:00.000Z",
    "walletId": 11,
    "walletName": "Tunai",
    "placeName": null
  },
  "wallet": {
    "id": 11,
    "name": "Tunai",
    "type": "cash",
    "balance": -5000,
    "displayBalance": -5000,
    "isDebt": false,
    "isReserved": false,
    "description": null,
    "sortOrder": 3,
    "spentThisMonth": 25000
  }
}
```

- `expense` shape (also §7–§9): `id`, `amount`, `category` (label or `null`),
  `note`, `source` (`"gaji"` when stored null), `date`, `createdAt`, `walletId`
  and `walletName` (`null` for an orphan row whose wallet was deleted on the web),
  `placeName` (always `null` from mobile).
- `wallet` = §2 item after the write (`null` only if the wallet vanished);
  `today` = §5 body without `ok` and `asOf`, computed after the commit.
- Paying from a reserved wallet is allowed (the app never makes it the default).

**Errors**, in order: `403` → `401` → `429` (guard) → `415` → `413` → `400` body
validation → (inside the transaction) `400 wallet_not_found` → `500`:
- `403` → `{"ok":false,"error":"forbidden_origin","message":"Permintaan dari situs lain tidak diizinkan."}`
- `401` → `{"ok":false,"error":"unauthorized","message":"Sesi sudah berakhir. Silakan masuk lagi."}`
- `429` → `{"ok":false,"error":"rate_limited","message":"Terlalu banyak permintaan. Coba lagi sebentar lagi."}`, `Retry-After: 2`
- `415` → `{"ok":false,"error":"unsupported_media_type","message":"Format permintaan harus JSON."}`
- `413` → `{"ok":false,"error":"payload_too_large","message":"Isi permintaan terlalu besar."}`
- `400` → `{"ok":false,"error":"bad_request","message":"Nominal harus berupa angka bulat antara 1 dan 100.000.000."}`
- `400` → `{"ok":false,"error":"bad_request","message":"Dompet wajib dipilih."}`: `walletId` missing or not a positive int32
- `400` → `{"ok":false,"error":"bad_request","message":"Kategori tidak dikenal."}`: not one of the 9 labels (keys like `makan_harian` are rejected)
- `400` → `{"ok":false,"error":"bad_request","message":"Catatan maksimal 120 karakter."}`
- `400` → `{"ok":false,"error":"bad_request","message":"Sumber dana harus gaji atau bonus."}`
- `400` → `{"ok":false,"error":"bad_request","message":"Tanggal harus berformat YYYY-MM-DD, paling lama 7 hari ke belakang atau besok."}`
- `400` → `{"ok":false,"error":"bad_request","message":"Isi permintaan harus berupa objek JSON."}`
- `400` → `{"ok":false,"error":"wallet_not_found","message":"Dompet tidak ditemukan. Pilih dompet lain."}`: wallet missing, another user's, or a
  legacy `userId = null` wallet for a user who is not the owner
- `500` → `{"ok":false,"error":"server_error","message":"Terjadi kesalahan di server. Coba lagi nanti."}` with
  **`Retry-After: 1`** when Postgres aborted the transaction
  (deadlock `40P01` / serialization `40001`, Prisma `P2034`): nothing was written,
  send the same request again (the 120 s dedupe covers a resend after a commit).
  Any other `500` has no `Retry-After`.

## 7. `GET /api/mobile/expenses?year=&month=`

One WIB month, default the current one. Newest first (`date desc, id desc`), at
most 500 rows; `total` and `count` cover the whole month, `more: true` when rows
were left out. List and sums come from one REPEATABLE READ transaction.

`GET /api/mobile/expenses` → **200** (the orphan row dated `2026-10-31T23:40Z` is
1 Nov 06:40 WIB, so it is in November; its legacy key `transport` is shown as `Transport`):
```json
{
  "ok": true,
  "asOf": "2026-11-01T07:00:00.000Z",
  "period": {
    "year": 2026,
    "month": 11
  },
  "total": 50000,
  "count": 3,
  "more": false,
  "expenses": [
    {
      "id": 499,
      "amount": 25000,
      "category": "Makan harian",
      "note": "nasi padang",
      "source": "gaji",
      "date": "2026-11-01T05:30:00.000Z",
      "createdAt": "2026-11-01T05:30:02.000Z",
      "walletId": 3,
      "walletName": "BCA",
      "placeName": null
    },
    {
      "id": 498,
      "amount": 10000,
      "category": "Transport",
      "note": null,
      "source": "gaji",
      "date": "2026-11-01T01:15:00.000Z",
      "createdAt": "2026-11-01T01:15:04.000Z",
      "walletId": 9,
      "walletName": "Kartu Kredit",
      "placeName": null
    },
    {
      "id": 497,
      "amount": 15000,
      "category": "Transport",
      "note": "ojek (dompet sudah dihapus)",
      "source": "gaji",
      "date": "2026-10-31T23:40:00.000Z",
      "createdAt": "2026-10-31T23:40:05.000Z",
      "walletId": null,
      "walletName": null,
      "placeName": null
    }
  ]
}
```

`GET /api/mobile/expenses?year=2026&month=10` → **200**
```json
{
  "ok": true,
  "asOf": "2026-11-01T07:00:00.000Z",
  "period": {
    "year": 2026,
    "month": 10
  },
  "total": 120000,
  "count": 1,
  "more": false,
  "expenses": [
    {
      "id": 480,
      "amount": 120000,
      "category": "Belanja kecil",
      "note": null,
      "source": "gaji",
      "date": "2026-10-30T05:00:00.000Z",
      "createdAt": "2026-10-30T05:00:10.000Z",
      "walletId": 3,
      "walletName": "BCA",
      "placeName": null
    }
  ]
}
```

**Errors**, in order:
- `401` → `{"ok":false,"error":"unauthorized","message":"Sesi sudah berakhir. Silakan masuk lagi."}`
- `429` → `{"ok":false,"error":"rate_limited","message":"Terlalu banyak permintaan. Coba lagi sebentar lagi."}`, `Retry-After: 1`
- `400` → `{"ok":false,"error":"bad_request","message":"Bulan atau tahun tidak valid."}`: only one of `year`/`month`,
  `year` outside 2020..2100, `month` outside 1..12, not digits, or a parameter repeated
  (`?year=2026&month=11&month=10`)
- `500 server_error` (no `Retry-After`)

## 8. `PATCH /api/mobile/expenses/{id}`

Partial body, field by field:

| Field | Left out | `null` | Value |
|---|---|---|---|
| `amount` | unchanged | 400 amount message | §6 rule |
| `walletId` | unchanged (orphan row: 400 "Dompet wajib dipilih.") | 400 "Dompet wajib dipilih." | user's wallet, else `400 wallet_not_found` |
| `category` | unchanged (a stored legacy key stays as stored) | cleared | label; `""` clears |
| `note` | unchanged | cleared | §6 rule; `""` clears |
| `source` | unchanged (stored `null` stays) | 400 source message | `gaji` / `bonus` |
| `date` | unchanged, **no** 7-day check | 400 date message (`""` too) | §6 rule; today keeps the stored time if it is already today (WIB), else becomes now |

A body with none of these fields → `400` "Tidak ada perubahan.". Sending a value
equal to the stored one is fine (200, nothing written). The row is locked
(`FOR UPDATE`), only changed columns are written, and wallet moves (undo on the
old wallet, apply on the new one) run in `walletId` order in the same transaction.

Request `PATCH /api/mobile/expenses/499` `{"amount": 30000}` → **200**
```json
{
  "ok": true,
  "expense": {
    "id": 499,
    "amount": 30000,
    "category": "Makan harian",
    "note": "nasi padang",
    "source": "gaji",
    "date": "2026-11-01T05:30:00.000Z",
    "createdAt": "2026-11-01T05:30:02.000Z",
    "walletId": 3,
    "walletName": "BCA",
    "placeName": null
  },
  "wallets": [
    {
      "id": 3,
      "name": "BCA",
      "type": "bank",
      "balance": 8245000,
      "displayBalance": 8245000,
      "isDebt": false,
      "isReserved": false,
      "description": null,
      "sortOrder": 0,
      "spentThisMonth": 30000
    }
  ],
  "today": {
    "date": "2026-11-01",
    "period": {
      "year": 2026,
      "month": 11,
      "daysInMonth": 30,
      "daysLeft": 30
    },
    "spent": {
      "today": 55000,
      "month": 55000
    },
    "savedThisMonth": 500000,
    "budget": {
      "status": "WITHIN_BUDGET",
      "limit": 4500000,
      "spent": 55000,
      "remaining": 4445000
    },
    "safeToday": {
      "basis": "budget",
      "state": "ok",
      "days": 30,
      "allowance": 150000,
      "spentToday": 55000,
      "remaining": 95000
    },
    "wallets": {
      "free": 7065000,
      "reserved": 3000000
    }
  }
}
```

Then `{"walletId": 9, "note": null}` (BCA gets the 30.000 back, Kartu Kredit owes
30.000 more) → **200**, `wallets` = both wallets, sorted by id:
```json
{
  "ok": true,
  "expense": {
    "id": 499,
    "amount": 30000,
    "category": "Makan harian",
    "note": null,
    "source": "gaji",
    "date": "2026-11-01T05:30:00.000Z",
    "createdAt": "2026-11-01T05:30:02.000Z",
    "walletId": 9,
    "walletName": "Kartu Kredit",
    "placeName": null
  },
  "wallets": [
    {
      "id": 3,
      "name": "BCA",
      "type": "bank",
      "balance": 8275000,
      "displayBalance": 8275000,
      "isDebt": false,
      "isReserved": false,
      "description": null,
      "sortOrder": 0,
      "spentThisMonth": 0
    },
    {
      "id": 9,
      "name": "Kartu Kredit",
      "type": "credit",
      "balance": 1230000,
      "displayBalance": -1230000,
      "isDebt": true,
      "isReserved": false,
      "description": null,
      "sortOrder": 2,
      "spentThisMonth": 40000
    }
  ],
  "today": {
    "date": "2026-11-01",
    "period": {
      "year": 2026,
      "month": 11,
      "daysInMonth": 30,
      "daysLeft": 30
    },
    "spent": {
      "today": 55000,
      "month": 55000
    },
    "savedThisMonth": 500000,
    "budget": {
      "status": "WITHIN_BUDGET",
      "limit": 4500000,
      "spent": 55000,
      "remaining": 4445000
    },
    "safeToday": {
      "basis": "budget",
      "state": "ok",
      "days": 30,
      "allowance": 150000,
      "spentToday": 55000,
      "remaining": 95000
    },
    "wallets": {
      "free": 7065000,
      "reserved": 3000000
    }
  }
}
```

`PATCH /api/mobile/expenses/497` `{"walletId": 3}` on the orphan row → **200**,
`wallets` = only the new wallet:
```json
{
  "ok": true,
  "expense": {
    "id": 497,
    "amount": 15000,
    "category": "Transport",
    "note": "ojek (dompet sudah dihapus)",
    "source": "gaji",
    "date": "2026-10-31T23:40:00.000Z",
    "createdAt": "2026-10-31T23:40:05.000Z",
    "walletId": 3,
    "walletName": "BCA",
    "placeName": null
  },
  "wallets": [
    {
      "id": 3,
      "name": "BCA",
      "type": "bank",
      "balance": 8260000,
      "displayBalance": 8260000,
      "isDebt": false,
      "isReserved": false,
      "description": null,
      "sortOrder": 0,
      "spentThisMonth": 15000
    }
  ],
  "today": {
    "date": "2026-11-01",
    "period": {
      "year": 2026,
      "month": 11,
      "daysInMonth": 30,
      "daysLeft": 30
    },
    "spent": {
      "today": 55000,
      "month": 55000
    },
    "savedThisMonth": 500000,
    "budget": {
      "status": "WITHIN_BUDGET",
      "limit": 4500000,
      "spent": 55000,
      "remaining": 4445000
    },
    "safeToday": {
      "basis": "budget",
      "state": "ok",
      "days": 30,
      "allowance": 150000,
      "spentToday": 55000,
      "remaining": 95000
    },
    "wallets": {
      "free": 7050000,
      "reserved": 3000000
    }
  }
}
```

**Errors**, in order: `403` → `401` → `429` (guard) → `404` bad path id → `415` →
`413` → `400` body validation → (inside the transaction) `404` missing/foreign row
→ `400` → `500`:
- `403` → `{"ok":false,"error":"forbidden_origin","message":"Permintaan dari situs lain tidak diizinkan."}`
- `404` → `{"ok":false,"error":"not_found","message":"Data tidak ditemukan."}`: path id not a positive int32 (uses one write token)
- `415` → `{"ok":false,"error":"unsupported_media_type","message":"Format permintaan harus JSON."}`
- `413` → `{"ok":false,"error":"payload_too_large","message":"Isi permintaan terlalu besar."}`
- `400` → `{"ok":false,"error":"bad_request","message":"Tidak ada perubahan."}`
- `400` → `{"ok":false,"error":"bad_request","message":"Nominal harus berupa angka bulat antara 1 dan 100.000.000."}`
- `400` → `{"ok":false,"error":"bad_request","message":"Tanggal harus berformat YYYY-MM-DD, paling lama 7 hari ke belakang atau besok."}`
- `404` → `{"ok":false,"error":"not_found","message":"Data tidak ditemukan."}`: row missing or another user's
- `400` → `{"ok":false,"error":"bad_request","message":"Dompet wajib dipilih."}`: orphan row and no `walletId` in the body
- `400` → `{"ok":false,"error":"wallet_not_found","message":"Dompet tidak ditemukan. Pilih dompet lain."}`
- every §6 field message
- `500 server_error`, with `Retry-After: 1` when retryable (§6)

## 9. `DELETE /api/mobile/expenses/{id}`

No body. Locks the row, deletes it and gives the amount back to its wallet (an
asset wallet goes up, a debt wallet goes down). No time limit.

`DELETE /api/mobile/expenses/499` → **200**
```json
{
  "ok": true,
  "deleted": {
    "id": 499,
    "amount": 25000
  },
  "wallet": {
    "id": 3,
    "name": "BCA",
    "type": "bank",
    "balance": 8275000,
    "displayBalance": 8275000,
    "isDebt": false,
    "isReserved": false,
    "description": null,
    "sortOrder": 0,
    "spentThisMonth": 0
  },
  "today": {
    "date": "2026-11-01",
    "period": {
      "year": 2026,
      "month": 11,
      "daysInMonth": 30,
      "daysLeft": 30
    },
    "spent": {
      "today": 25000,
      "month": 25000
    },
    "savedThisMonth": 500000,
    "budget": {
      "status": "WITHIN_BUDGET",
      "limit": 4500000,
      "spent": 25000,
      "remaining": 4475000
    },
    "safeToday": {
      "basis": "budget",
      "state": "ok",
      "days": 30,
      "allowance": 150000,
      "spentToday": 25000,
      "remaining": 125000
    },
    "wallets": {
      "free": 7095000,
      "reserved": 3000000
    }
  }
}
```

`DELETE /api/mobile/expenses/497` (orphan row) → **200**, `wallet: null`:
```json
{
  "ok": true,
  "deleted": {
    "id": 497,
    "amount": 15000
  },
  "wallet": null,
  "today": {
    "date": "2026-11-01",
    "period": {
      "year": 2026,
      "month": 11,
      "daysInMonth": 30,
      "daysLeft": 30
    },
    "spent": {
      "today": 10000,
      "month": 10000
    },
    "savedThisMonth": 500000,
    "budget": {
      "status": "WITHIN_BUDGET",
      "limit": 4500000,
      "spent": 10000,
      "remaining": 4490000
    },
    "safeToday": {
      "basis": "budget",
      "state": "ok",
      "days": 30,
      "allowance": 150000,
      "spentToday": 10000,
      "remaining": 140000
    },
    "wallets": {
      "free": 7095000,
      "reserved": 3000000
    }
  }
}
```

**Errors**, in order: `403` → `401` → `429` (guard) → `404` → `500`:
- `403` → `{"ok":false,"error":"forbidden_origin","message":"Permintaan dari situs lain tidak diizinkan."}`
- `401` → `{"ok":false,"error":"unauthorized","message":"Sesi sudah berakhir. Silakan masuk lagi."}`
- `404` → `{"ok":false,"error":"not_found","message":"Data tidak ditemukan."}`: bad path id, missing (also the second
  of two deletes), or another user's row
- `500 server_error`, with `Retry-After: 1` when retryable (§6). No `413`/`415`.

## 10. Goals (v1) under the v2 guards

`POST /api/mobile/goals` now runs `guardWrite` and `readJsonBody`:
- `403` → `{"ok":false,"error":"forbidden_origin","message":"Permintaan dari situs lain tidak diizinkan."}`
- `429 rate_limited` (shares the 30/min write bucket)
- `413` → `{"ok":false,"error":"payload_too_large","message":"Isi permintaan terlalu besar."}`

Everything else (`GET /api/mobile/goals`, `GET /api/mobile/goals/{id}`, the POST
body and responses) is unchanged from v1.

## 11. Not for the app

`/api/cyrene/*`, `/api/expenses`, `/api/stats`, legacy `POST /api/expense` and
`POST /api/contribution` (still used for deposits in v2, see v1 contract §5).

## 12. Decisions reflected here

- **Overdraft on asset wallets is allowed.** Expense POST/PATCH never check the
  balance; non-debt wallets (reserved included) may go negative. Negative asset
  balances count as is in `assets`, `free` and the wallet basis of `safeToday`;
  only `safeToday.allowance` is floored at 0. Debt wallets only go up on spending.
  (SPEC-v2 §12 K14.)
- **Expense read range for `today`**: from the start of the WIB month, no upper
  bound (§5). (SPEC-v2 §3.4, §12 K15.)
- **Email case normalization** at sign-in (§1). (SPEC-v2 §12 K16.)
