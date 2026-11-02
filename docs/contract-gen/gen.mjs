// Contract generator for tepira /api/mobile/* v2. Calls the REAL route handlers
// of a tepira checkout (TEPIRA_REPO, default /tmp/tepira-main) through that
// repo's own handler-test harness (test/harness: fake Prisma, stub auth, stub
// next/cache, fixed clock 2026-11-01T07:00:00.000Z). Prints JSON records.
//
// Run: see README.md in this directory.
import { createRequire } from "node:module";
import { createSign, generateKeyPairSync } from "node:crypto";

const REPO = process.env.TEPIRA_REPO;
if (!REPO) throw new Error("set TEPIRA_REPO to a tepira checkout (absolute path) with node_modules");
await import(REPO + "/test/harness/clock.mjs");
const NOW = Date.now();

// --- Google ID tokens signed by a local key (google-auth-library cert fetch patched)
const req = createRequire(REPO + "/package.json");
const { OAuth2Client } = req("google-auth-library");
const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
OAuth2Client.prototype.getFederatedSignonCertsAsync = async () => ({
  certs: { k1: publicKey.export({ type: "spki", format: "pem" }) },
});
const AUD = "1234567890-android.apps.googleusercontent.com";
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
function idToken(o = {}) {
  const now = Math.floor(NOW / 1000);
  const h = b64({ alg: "RS256", typ: "JWT", kid: "k1" });
  const p = b64({
    iss: "https://accounts.google.com", aud: AUD, sub: "google-sub-rina", email: "rina@example.test", email_verified: true,
    name: "Rina Contoh", picture: "https://example.test/avatar/rina.png", iat: now - 10, exp: now + 3600, ...o,
  });
  const s = createSign("RSA-SHA256");
  s.update(`${h}.${p}`);
  return `${h}.${p}.${s.sign(privateKey).toString("base64url")}`;
}

const APP = "https://tepira.example.test";
Object.assign(process.env, {
  AUTH_SECRET: "contract-secret-0123456789abcdef0123456789",
  AUTH_URL: APP,
  TEPIRA_DEFAULT_USER_EMAIL: "owner@tepira.example.test",
  TEPIRA_ALLOWED_EMAILS: "rina@example.test,budi@example.test",
});
delete process.env.NEXTAUTH_URL;
delete process.env.TEPIRA_MOBILE_GOOGLE_CLIENT_IDS;

const { fake, prisma } = await import("@/lib/prisma");
const { authState } = await import("@/lib/auth");
const http = await import("@/lib/mobile/http");
const { NextRequest } = await import("next/server");
const session = await import(REPO + "/app/api/mobile/session/route.ts");
const wallets = await import(REPO + "/app/api/mobile/wallets/route.ts");
const walletId = await import(REPO + "/app/api/mobile/wallets/[id]/route.ts");
const today = await import(REPO + "/app/api/mobile/today/route.ts");
const expenses = await import(REPO + "/app/api/mobile/expenses/route.ts");
const expenseId = await import(REPO + "/app/api/mobile/expenses/[id]/route.ts");
const goals = await import(REPO + "/app/api/mobile/goals/route.ts");

// The fake has no Account model and no nested writes: add just what the
// session route's UserStore uses (account.findUnique with user select;
// user.create with accounts.create).
const accounts = [];
prisma.account = {
  async findUnique({ where }) {
    const key = where.provider_providerAccountId;
    const acc = accounts.find((a) => a.provider === key.provider && a.providerAccountId === key.providerAccountId);
    if (!acc) return null;
    const u = fake.row("user", acc.userId);
    return { user: { id: u.id, name: u.name, email: u.email, image: u.image } };
  },
};
const userCreate = prisma.user.create;
prisma.user.create = async ({ data, select }) => {
  const { accounts: nested, ...rest } = data;
  const id = `user_${String(fake.tables.user.length + 1).padStart(3, "0")}`;
  const u = await userCreate({ data: { id, ...rest, createdAt: new Date() }, select });
  if (nested?.create) accounts.push({ ...nested.create, userId: id });
  return u;
};

const ME = "user_owner";
function seed() {
  accounts.length = 0;
  fake.reset({
    user: [
      { id: ME, name: "Owner", email: "owner@tepira.example.test", image: null, createdAt: new Date("2026-01-01T00:00:00Z") },
      { id: "user_rina", name: "Rina Contoh", email: "rina@example.test", image: "https://example.test/avatar/rina.png", createdAt: new Date("2026-02-01T00:00:00Z") },
      // Stored with capitals by an older web sign-in; no Google account linked.
      { id: "user_budi", name: "Budi", email: "Budi@Example.test", image: null, createdAt: new Date("2026-03-01T00:00:00Z") },
    ],
    wallet: [
      { id: 3, userId: ME, name: "BCA", type: "bank", balance: 8_250_000, sortOrder: 0, createdAt: new Date("2026-01-02T00:00:00Z") },
      { id: 7, userId: ME, name: "Tabungan Kurban", type: "bank", balance: 3_000_000, isReserved: true, description: "Kurban 2027", sortOrder: 1, createdAt: new Date("2026-01-03T00:00:00Z") },
      { id: 9, userId: ME, name: "Kartu Kredit", type: "credit", balance: 1_200_000, isDebt: true, sortOrder: 2, createdAt: new Date("2026-01-04T00:00:00Z") },
      { id: 11, userId: ME, name: "Tunai", type: "cash", balance: 20_000, sortOrder: 3, createdAt: new Date("2026-01-05T00:00:00Z") },
      { id: 40, userId: "user_other", name: "Dompet orang lain", type: "bank", balance: 1_000, sortOrder: 0 },
    ],
    expense: [
      { id: 480, userId: ME, walletId: 3, amount: 120_000, category: "Belanja kecil", note: null, source: "gaji", date: new Date("2026-10-30T05:00:00.000Z"), createdAt: new Date("2026-10-30T05:00:10.000Z") },
      { id: 497, userId: ME, walletId: null, amount: 15_000, category: "transport", note: "ojek (dompet sudah dihapus)", source: null, date: new Date("2026-10-31T23:40:00.000Z"), createdAt: new Date("2026-10-31T23:40:05.000Z") },
      { id: 498, userId: ME, walletId: 9, amount: 10_000, category: "Transport", note: null, source: "gaji", date: new Date("2026-11-01T01:15:00.000Z"), createdAt: new Date("2026-11-01T01:15:04.000Z") },
      { id: 499, userId: ME, walletId: 3, amount: 25_000, category: "Makan harian", note: "nasi padang", source: "gaji", date: new Date("2026-11-01T05:30:00.000Z"), createdAt: new Date("2026-11-01T05:30:02.000Z") },
    ],
    salary: [{ id: 1, userId: ME, month: 11, year: 2026 }],
    salaryAllocation: [
      { id: 1, salaryId: 1, category: "Makan harian", amount: 1_500_000 },
      { id: 2, salaryId: 1, category: "Transport", amount: 600_000 },
      { id: 3, salaryId: 1, category: "Listrik / Air / Kos", amount: 1_500_000 },
      { id: 4, salaryId: 1, category: "Pulsa & Internet", amount: 200_000 },
      { id: 5, salaryId: 1, category: "Nongkrong / jajan", amount: 700_000 },
    ],
    goal: [{ id: 12, userId: ME, title: "Laptop kerja", targetAmount: 15_000_000, createdAt: new Date("2026-06-01T03:15:00Z") }],
    contribution: [{ id: 150, goalId: 12, amount: 500_000, note: null, date: new Date("2026-11-01T02:00:00.000Z") }],
  });
  authState.userId = ME;
  http.mobileWriteLimiter["buckets"].clear();
  http.mobileReadLimiter["buckets"].clear();
}

const KEEP = ["content-type", "cache-control", "vary", "retry-after", "x-content-type-options", "referrer-policy"];
const out = [];
async function show(label, request, resP) {
  const res = await resP;
  const headers = Object.fromEntries(KEEP.filter((h) => res.headers.get(h)).map((h) => [h, res.headers.get(h)]));
  const body = await res.json();
  out.push({ label, request, status: res.status, headers, body });
  return body;
}
let ipSeq = 0;
const nextIp = () => `203.0.113.${++ipSeq}`;
function mk(method, path, body, { ct = "application/json", headers = {}, ip } = {}) {
  const h = { "x-real-ip": ip ?? nextIp(), ...headers };
  if (body !== undefined && ct) h["content-type"] = ct;
  return new NextRequest(APP + path, {
    method,
    headers: h,
    body: body === undefined ? undefined : typeof body === "string" ? body : JSON.stringify(body),
  });
}
const params = (id) => ({ params: Promise.resolve({ id: String(id) }) });
const desc = (method, path, body, extra) => ({ method, path, ...(body !== undefined ? { body } : {}), ...(extra ?? {}) });

// ---------------------------------------------------------------- session
const S = "/api/mobile/session";
seed();
await show("session: 404 disabled (env unset)", desc("POST", S, { idToken: "<token>" }), session.POST(mk("POST", S, { idToken: idToken() })));
process.env.TEPIRA_MOBILE_GOOGLE_CLIENT_IDS = `${AUD}, 1234567890-ios.apps.googleusercontent.com`;
await show("session: 200 first sign-in, email normalized", desc("POST", S, { idToken: "<token: sub google-sub-new, email '  Rina.Baru@Example.TEST '>" }),
  (process.env.TEPIRA_ALLOWED_EMAILS += ",rina.baru@example.test", session.POST(mk("POST", S, { idToken: idToken({ sub: "google-sub-new", email: "  Rina.Baru@Example.TEST ", name: "Rina Baru" }) }))));
accounts.push({ provider: "google", providerAccountId: "google-sub-rina", userId: "user_rina" });
await show("session: 200 linked account", desc("POST", S, { idToken: "<token>" }), session.POST(mk("POST", S, { idToken: idToken() })));
await show("session: 400 bad_request", desc("POST", S, { token: "x" }), session.POST(mk("POST", S, { token: "x" })));
await show("session: 401 invalid_token", desc("POST", S, { idToken: "<token with another aud>" }), session.POST(mk("POST", S, { idToken: idToken({ aud: "other.apps.googleusercontent.com" }) })));
await show("session: 403 not_allowed", desc("POST", S, { idToken: "<token: stranger@example.test>" }), session.POST(mk("POST", S, { idToken: idToken({ sub: "g-stranger", email: "stranger@example.test" }) })));
await show("session: 403 account_not_linked (stored 'Budi@Example.test', token 'budi@example.test')", desc("POST", S, { idToken: "<token: budi@example.test, unlinked sub>" }),
  session.POST(mk("POST", S, { idToken: idToken({ sub: "google-sub-budi", email: "budi@example.test", name: "Budi" }) })));
await show("session: 403 forbidden_origin", desc("POST", S, { idToken: "<token>" }, { headers: { Origin: "https://evil.example" } }),
  session.POST(mk("POST", S, { idToken: idToken() }, { headers: { origin: "https://evil.example" } })));
await show("session: 415", desc("POST", S, "idToken=x", { headers: { "Content-Type": "text/plain" } }), session.POST(mk("POST", S, "idToken=x", { ct: "text/plain" })));
await show("session: 413", desc("POST", S, "<65537-byte JSON body>"), session.POST(mk("POST", S, JSON.stringify({ idToken: "x".repeat(65_537) }))));
for (let i = 0; i < 10; i++) await session.POST(mk("POST", S, { token: "x" }, { ip: "198.51.100.9" }));
await show("session: 429 rate_limited (11th attempt from one IP in a minute)", desc("POST", S, { idToken: "<token>" }),
  session.POST(mk("POST", S, { idToken: idToken() }, { ip: "198.51.100.9" })));

// ---------------------------------------------------------------- wallets
const W = "/api/mobile/wallets";
seed();
await show("wallets GET: 200", desc("GET", W), wallets.GET());
await show("wallets POST: 201 reserved wallet", desc("POST", W, { name: "Dana Darurat", type: "bank", balance: 2_000_000, isReserved: true, description: "Jangan dipakai" }),
  wallets.POST(mk("POST", W, { name: "Dana Darurat", type: "bank", balance: 2_000_000, isReserved: true, description: "Jangan dipakai" })));
await show("wallets POST: 201 paylater (isDebt forced)", desc("POST", W, { name: "Paylater", type: "paylater", balance: 350_000 }),
  wallets.POST(mk("POST", W, { name: "Paylater", type: "paylater", balance: 350_000 })));
for (const [label, body] of [
  ["name", { name: "  ", type: "bank" }],
  ["type", { name: "X", type: "crypto" }],
  ["balance", { name: "X", type: "bank", balance: 10.5 }],
  ["negative debt", { name: "X", type: "credit", balance: -1 }],
  ["isDebt type", { name: "X", type: "bank", isDebt: "ya" }],
  ["isReserved type", { name: "X", type: "bank", isReserved: 1 }],
  ["debt + reserved", { name: "X", type: "credit", isReserved: true }],
  ["description", { name: "X", type: "bank", description: "d".repeat(201) }],
  ["body", [1, 2]],
]) await show(`wallets POST: 400 ${label}`, desc("POST", W, body), wallets.POST(mk("POST", W, body)));
await show("wallets POST: 403 forbidden_origin", desc("POST", W, { name: "X", type: "bank" }, { headers: { "Sec-Fetch-Site": "cross-site" } }),
  wallets.POST(mk("POST", W, { name: "X", type: "bank" }, { headers: { "sec-fetch-site": "cross-site" } })));
await show("wallets POST: 415", desc("POST", W, "name=X", { headers: { "Content-Type": "text/plain" } }), wallets.POST(mk("POST", W, "name=X", { ct: "text/plain" })));
await show("wallets POST: 413", desc("POST", W, "<65537-byte JSON body>"), wallets.POST(mk("POST", W, JSON.stringify({ name: "X", type: "bank", description: "d".repeat(65_537) }))));
authState.userId = null;
await show("wallets GET: 401", desc("GET", W), wallets.GET());
await show("wallets POST: 401", desc("POST", W, { name: "X", type: "bank" }), wallets.POST(mk("POST", W, { name: "X", type: "bank" })));
authState.userId = ME;

seed();
await show("wallet PATCH: 200 rename, clear description", desc("PATCH", `${W}/3`, { name: "BCA Utama", description: null }),
  walletId.PATCH(mk("PATCH", `${W}/3`, { name: "BCA Utama", description: null }), params(3)));
await show("wallet PATCH: 400 no change (empty body)", desc("PATCH", `${W}/3`, {}), walletId.PATCH(mk("PATCH", `${W}/3`, {}), params(3)));
await show("wallet PATCH: 400 no change (isDebt same as stored)", desc("PATCH", `${W}/3`, { isDebt: false }), walletId.PATCH(mk("PATCH", `${W}/3`, { isDebt: false }), params(3)));
await show("wallet PATCH: 400 debt locked (isDebt)", desc("PATCH", `${W}/3`, { isDebt: true }), walletId.PATCH(mk("PATCH", `${W}/3`, { isDebt: true }), params(3)));
await show("wallet PATCH: 400 debt locked (type credit on asset)", desc("PATCH", `${W}/3`, { type: "credit" }), walletId.PATCH(mk("PATCH", `${W}/3`, { type: "credit" }), params(3)));
await show("wallet PATCH: 400 reserved debt", desc("PATCH", `${W}/9`, { isReserved: true }), walletId.PATCH(mk("PATCH", `${W}/9`, { isReserved: true }), params(9)));
await show("wallet PATCH: 400 null name", desc("PATCH", `${W}/3`, { name: null }), walletId.PATCH(mk("PATCH", `${W}/3`, { name: null }), params(3)));
await show("wallet PATCH: 404 other user's wallet", desc("PATCH", `${W}/40`, { name: "X" }), walletId.PATCH(mk("PATCH", `${W}/40`, { name: "X" }), params(40)));
await show("wallet PATCH: 404 bad id", desc("PATCH", `${W}/abc`, { name: "X" }), walletId.PATCH(mk("PATCH", `${W}/abc`, { name: "X" }), params("abc")));

// ---------------------------------------------------------------- today
const T = "/api/mobile/today";
seed();
await show("today GET: 200 budget basis", desc("GET", T), today.GET());
fake.tables.salary.length = 0;
fake.tables.salaryAllocation.length = 0;
await show("today GET: 200 wallet basis (NO_BUDGET)", desc("GET", T), today.GET());
// Overdraft: Tunai has 20.000, spend 25.000 from it -> -5.000 counts into free as is.
await expenses.POST(mk("POST", "/api/mobile/expenses", { amount: 25_000, walletId: 11, category: "Nongkrong / jajan" }));
await show("today GET: 200 wallet basis after overdraft on Tunai", desc("GET", T), today.GET());
authState.userId = null;
await show("today GET: 401", desc("GET", T), today.GET());

// ---------------------------------------------------------------- expenses POST
const E = "/api/mobile/expenses";
seed();
const newBody = { amount: 18_000, walletId: 3, category: "Makan harian", note: "bakso" };
await show("expenses POST: 201 created", desc("POST", E, newBody), expenses.POST(mk("POST", E, newBody)));
await show("expenses POST: 200 deduped (same body again within 120 s)", desc("POST", E, newBody), expenses.POST(mk("POST", E, newBody)));
await show("expenses POST: 201 dated yesterday, bonus, debt wallet", desc("POST", E, { amount: 40_000, walletId: 9, category: null, source: "bonus", date: "2026-10-31" }),
  expenses.POST(mk("POST", E, { amount: 40_000, walletId: 9, category: null, source: "bonus", date: "2026-10-31" })));
await show("expenses POST: 201 overdraft (Tunai 20.000 - 25.000)", desc("POST", E, { amount: 25_000, walletId: 11 }), expenses.POST(mk("POST", E, { amount: 25_000, walletId: 11 })));
await show("expenses POST: 400 wallet_not_found", desc("POST", E, { amount: 5_000, walletId: 40 }), expenses.POST(mk("POST", E, { amount: 5_000, walletId: 40 })));
for (const [label, body] of [
  ["amount", { amount: 0, walletId: 3 }],
  ["wallet", { amount: 5_000 }],
  ["category", { amount: 5_000, walletId: 3, category: "makan_harian" }],
  ["note", { amount: 5_000, walletId: 3, note: "n".repeat(121) }],
  ["source", { amount: 5_000, walletId: 3, source: "tabungan" }],
  ["date", { amount: 5_000, walletId: 3, date: "2026-10-20" }],
  ["body", "null"],
]) await show(`expenses POST: 400 ${label}`, desc("POST", E, typeof body === "string" ? JSON.parse(body) : body), expenses.POST(mk("POST", E, body)));
await show("expenses POST: 415", desc("POST", E, "amount=1", { headers: { "Content-Type": "text/plain" } }), expenses.POST(mk("POST", E, "amount=1", { ct: "text/plain" })));
await show("expenses POST: 413", desc("POST", E, "<65537-byte JSON body>"), expenses.POST(mk("POST", E, JSON.stringify({ amount: 1, walletId: 3, note: "n".repeat(65_537) }))));
await show("expenses POST: 403 forbidden_origin (Origin not AUTH_URL)", desc("POST", E, newBody, { headers: { Origin: "https://evil.example" } }),
  expenses.POST(mk("POST", E, newBody, { headers: { origin: "https://evil.example" } })));
http.mobileWriteLimiter["buckets"].clear();
for (let i = 0; i < 30; i++) await expenses.POST(mk("POST", E, { amount: 0, walletId: 3 }));
await show("expenses POST: 429 rate_limited (31st write in a minute)", desc("POST", E, newBody), expenses.POST(mk("POST", E, newBody)));
http.mobileWriteLimiter["buckets"].clear();
fake.onRaw(() => { throw Object.assign(new Error("deadlock"), { code: "P2034" }); });
await show("expenses POST: 500 retryable (deadlock/serialization)", desc("POST", E, newBody), expenses.POST(mk("POST", E, { ...newBody, amount: 19_000 })));
fake.onRaw(() => []);
authState.userId = null;
await show("expenses POST: 401", desc("POST", E, newBody), expenses.POST(mk("POST", E, newBody)));
authState.userId = ME;

// ---------------------------------------------------------------- expenses GET
seed();
await show("expenses GET: 200 current WIB month", desc("GET", E), expenses.GET(new NextRequest(APP + E)));
await show("expenses GET: 200 ?year=2026&month=10", desc("GET", `${E}?year=2026&month=10`), expenses.GET(new NextRequest(`${APP}${E}?year=2026&month=10`)));
for (const q of ["?year=2026", "?year=2026&month=13", "?year=2026&month=11&month=10", "?year=1999&month=1"]) {
  await show(`expenses GET: 400 ${q}`, desc("GET", E + q), expenses.GET(new NextRequest(APP + E + q)));
}
for (let i = 0; i < 60; i++) await expenses.GET(new NextRequest(APP + E));
await show("expenses GET: 429 rate_limited (61st read in a minute)", desc("GET", E), expenses.GET(new NextRequest(APP + E)));
authState.userId = null;
await show("expenses GET: 401", desc("GET", E), expenses.GET(new NextRequest(APP + E)));
authState.userId = ME;

// ---------------------------------------------------------------- expenses PATCH / DELETE
seed();
await show("expense PATCH: 200 amount only", desc("PATCH", `${E}/499`, { amount: 30_000 }), expenseId.PATCH(mk("PATCH", `${E}/499`, { amount: 30_000 }), params(499)));
await show("expense PATCH: 200 move to another wallet, clear note", desc("PATCH", `${E}/499`, { walletId: 9, note: null }),
  expenseId.PATCH(mk("PATCH", `${E}/499`, { walletId: 9, note: null }), params(499)));
await show("expense PATCH: 200 orphan row gets a wallet, legacy category key kept", desc("PATCH", `${E}/497`, { walletId: 3 }),
  expenseId.PATCH(mk("PATCH", `${E}/497`, { walletId: 3 }), params(497)));
seed();
await show("expense PATCH: 400 orphan row, no walletId (wallet_required)", desc("PATCH", `${E}/497`, { amount: 16_000 }),
  expenseId.PATCH(mk("PATCH", `${E}/497`, { amount: 16_000 }), params(497)));
await show("expense PATCH: 400 no change", desc("PATCH", `${E}/499`, { foo: 1 }), expenseId.PATCH(mk("PATCH", `${E}/499`, { foo: 1 }), params(499)));
await show("expense PATCH: 400 null amount", desc("PATCH", `${E}/499`, { amount: null }), expenseId.PATCH(mk("PATCH", `${E}/499`, { amount: null }), params(499)));
await show("expense PATCH: 400 null date", desc("PATCH", `${E}/499`, { date: null }), expenseId.PATCH(mk("PATCH", `${E}/499`, { date: null }), params(499)));
await show("expense PATCH: 400 wallet_not_found", desc("PATCH", `${E}/499`, { walletId: 40 }), expenseId.PATCH(mk("PATCH", `${E}/499`, { walletId: 40 }), params(499)));
await show("expense PATCH: 404 missing", desc("PATCH", `${E}/9999`, { amount: 1 }), expenseId.PATCH(mk("PATCH", `${E}/9999`, { amount: 1 }), params(9999)));
await show("expense PATCH: 404 bad id", desc("PATCH", `${E}/0`, { amount: 1 }), expenseId.PATCH(mk("PATCH", `${E}/0`, { amount: 1 }), params(0)));
await show("expense PATCH: 415", desc("PATCH", `${E}/499`, "amount=1", { headers: { "Content-Type": "text/plain" } }), expenseId.PATCH(mk("PATCH", `${E}/499`, "amount=1", { ct: "text/plain" }), params(499)));
await show("expense PATCH: 413", desc("PATCH", `${E}/499`, "<65537-byte JSON body>"), expenseId.PATCH(mk("PATCH", `${E}/499`, JSON.stringify({ note: "n".repeat(65_537) })), params(499)));
await show("expense PATCH: 403 forbidden_origin", desc("PATCH", `${E}/499`, { amount: 1 }, { headers: { "Sec-Fetch-Site": "same-site" } }),
  expenseId.PATCH(mk("PATCH", `${E}/499`, { amount: 1 }, { headers: { "sec-fetch-site": "same-site" } }), params(499)));
seed();
await show("expense DELETE: 200", desc("DELETE", `${E}/499`), expenseId.DELETE(mk("DELETE", `${E}/499`), params(499)));
await show("expense DELETE: 200 orphan (wallet null)", desc("DELETE", `${E}/497`), expenseId.DELETE(mk("DELETE", `${E}/497`), params(497)));
await show("expense DELETE: 404 already deleted", desc("DELETE", `${E}/499`), expenseId.DELETE(mk("DELETE", `${E}/499`), params(499)));
await show("expense DELETE: 403 forbidden_origin", desc("DELETE", `${E}/498`, undefined, { headers: { Origin: "https://evil.example" } }),
  expenseId.DELETE(mk("DELETE", `${E}/498`, undefined, { headers: { origin: "https://evil.example" } }), params(498)));
authState.userId = null;
await show("expense DELETE: 401", desc("DELETE", `${E}/498`), expenseId.DELETE(mk("DELETE", `${E}/498`), params(498)));
authState.userId = ME;

// ---------------------------------------------------------------- goals (guard changes only)
seed();
await show("goals POST: 403 forbidden_origin", desc("POST", "/api/mobile/goals", { title: "X", target: 1 }, { headers: { Origin: "https://evil.example" } }),
  goals.POST(mk("POST", "/api/mobile/goals", { title: "X", target: 1 }, { headers: { origin: "https://evil.example" } })));
await show("goals POST: 413", desc("POST", "/api/mobile/goals", "<65537-byte JSON body>"),
  goals.POST(mk("POST", "/api/mobile/goals", JSON.stringify({ title: "X", target: 1, description: "d".repeat(65_537) }))));

console.log(JSON.stringify(out, null, 2));
