// node render.mjs template.md out.json > api-contract-v2.md
// {{json LABEL}}  → fenced JSON of the response body (session token shortened)
// {{err LABEL}}   → "`STATUS` → `{one-line body}`"
// {{status LABEL}} / {{retry LABEL}} → status code / Retry-After header
import { readFileSync } from "node:fs";
const [tpl, data] = process.argv.slice(2);
const records = JSON.parse(readFileSync(data, "utf8"));
const used = new Set();
const get = (label) => {
  const r = records.find((x) => x.label === label.trim());
  if (!r) throw new Error(`no record: ${label}`);
  used.add(r.label);
  return r;
};
const shorten = (body) =>
  typeof body.token === "string" ? { ...body, token: body.token.slice(0, 40) + "…(Auth.js JWE, ~" + Math.round(body.token.length / 10) * 10 + " chars)" } : body;
const out = readFileSync(tpl, "utf8").replace(/\{\{(json|err|status|retry|pick) ([^}]+)\}\}/g, (_, kind, label) => {
  let keys = null;
  if (kind === "pick") [label, keys] = label.split("|");
  const r = get(label);
  if (kind === "pick") return "```json\n" + JSON.stringify(Object.fromEntries(keys.split(",").map((k) => [k, r.body[k]])), null, 2) + "\n```";
  if (kind === "json") return "```json\n" + JSON.stringify(shorten(r.body), null, 2) + "\n```";
  if (kind === "err") return "`" + r.status + "` → `" + JSON.stringify(r.body) + "`";
  if (kind === "status") return String(r.status);
  return r.headers["retry-after"] ?? "(none)";
});
process.stdout.write(out);
const unused = records.filter((r) => !used.has(r.label)).map((r) => r.label);
if (unused.length) process.stderr.write("unused records:\n  " + unused.join("\n  ") + "\n");
