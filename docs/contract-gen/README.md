# Contract generator for `docs/api-contract-v2.md`

Calls the real `/api/mobile/*` route handlers of a `tepira` checkout through that
repo's handler-test harness (`test/harness/`: fake Prisma, stub `@/lib/auth`, stub
`next/cache`, fixed clock `2026-11-01T07:00:00.000Z`), then fills
`template.md` with the verbatim responses. Nothing here talks to a database or
the network (Google certificates are replaced by a local key).

Not part of the Flutter build or tests.

## Run

Needs Node 22+ and a `tepira` checkout with `node_modules` installed (the
contract in this repo was generated from `main` at `f74d790`).

```sh
cd docs/contract-gen
export TEPIRA_REPO=/abs/path/to/tepira      # absolute path
node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON --import ./reg.mjs gen.mjs > /tmp/out.json
node render.mjs template.md /tmp/out.json > ../api-contract-v2.md
```

The output is deterministic (the session token is shortened). `render.mjs`
fails on a placeholder with no matching record and lists records the template
does not use on stderr.

## Files

- `gen.mjs`: seeds fictional data and records every request/response
  (`label`, `request`, `status`, headers, body).
- `reg.mjs`: `--import` hook that registers tepira's `test/harness/hooks.mjs`.
- `render.mjs`: replaces `{{json LABEL}}`, `{{pick LABEL|key,key}}`,
  `{{err LABEL}}`, `{{status LABEL}}` and `{{retry LABEL}}` in the template.
- `template.md`: the prose of the contract.
