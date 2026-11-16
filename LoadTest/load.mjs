// 1,000 Matchday players at once, against the local Firebase emulators with the real firestore.rules.
// Mirrors the app: EmailAuth.swift (sign-up / sign-in / lookup / token refresh, token reused for the round)
// and Leaderboard.swift (score PATCH after every answer, players GET + PATCH once per round, runQuery
// top 5 on the Games hub and top 10 on the full board, 3 tries with jittered backoff).
// Run: see README.md in this folder.
const USERS = Number(process.env.USERS || 1000);
const AUTH = "http://127.0.0.1:9099", FS = "http://127.0.0.1:8080";
const P = "demo-matchday", KEY = "fake-api-key";
const DOCS = `${FS}/v1/projects/${P}/databases/(default)/documents`;
const today = Math.floor(Date.now() / 86400000);
const stats = {}; const errors = {};
const sleep = ms => new Promise(r => setTimeout(r, ms));
function note(op, ms, ok, why) {
  (stats[op] ??= { n: 0, fail: 0, t: [] });
  stats[op].n++; stats[op].t.push(ms);
  if (!ok) { stats[op].fail++; const k = `${op}: ${why}`; errors[k] = (errors[k] || 0) + 1; }
}
let reads = 0, writes = 0;
async function call(op, url, opts = {}) {
  // Same as the app: up to 3 tries on dropped connections / busy / server errors, with jitter.
  for (let attempt = 0; ; attempt++) {
    const r = await once(op, url, opts);
    const transient = r.status === -1 || r.status === 429 || r.status >= 500;
    if (!transient || attempt >= 2) return r;
    await sleep(600 * 3 ** attempt * (0.7 + Math.random() * 0.6));
  }
}
async function once(op, url, { method = "POST", body, token, expect = "ok", okStatus = [] } = {}) {
  const t = performance.now();
  let status = 0, json = {};
  try {
    const r = await fetch(url, { method, headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
                                 body: body ? JSON.stringify(body) : undefined });
    status = r.status; json = await r.json().catch(() => ({}));
  } catch (e) { status = -1; json = { error: { message: String(e.cause?.code || e.message) } }; }
  const ok = expect === "denied" ? status === 403 : (status >= 200 && status < 300) || okStatus.includes(status);
  if (op.startsWith("fs.")) { if (method === "PATCH") writes++; else if (op.startsWith("fs.leaderboard")) reads += (Array.isArray(json) ? json.filter(x => x.document).length || 1 : 1); else reads++; }
  note(op, performance.now() - t, ok, status + " " + (json.error?.message || "").slice(0, 60));
  return { ok, status, json };
}
const int = n => ({ integerValue: String(n) }), str = s => ({ stringValue: s }), ts = () => ({ timestampValue: new Date().toISOString() });
const mask = f => Object.keys(f).sort().map(k => `updateMask.fieldPaths=${k}`).join("&");
const points = (right, secs) => right ? 100 + Math.round(50 * Math.max(0, 1 - secs / 20)) : 0;

const expected = {};
async function player(i, start) {
  await start;
  const email = i % 2 === 0, name = `load${String(i).padStart(4, "0")}`;
  // Sign in like the app: email accounts sign up + sign in + check verification; others go anonymous.
  let session;
  if (email) {
    const s = await call("auth.signUp(email)", `${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=${KEY}`,
      { body: { email: `${name}@example.com`, password: "Matchday-load-1", returnSecureToken: true } });
    if (!s.ok) return;
    session = (await call("auth.signIn(password)", `${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${KEY}`,
      { body: { email: `${name}@example.com`, password: "Matchday-load-1", returnSecureToken: true } })).json;
    await call("auth.lookup", `${AUTH}/identitytoolkit.googleapis.com/v1/accounts:lookup?key=${KEY}`, { body: { idToken: session.idToken } });
  } else {
    session = (await call("auth.signUp(anonymous)", `${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=${KEY}`,
      { body: { returnSecureToken: true } })).json;
  }
  if (!session?.idToken) return;
  let refresh = session.refreshToken; const uid = session.localId;
  let cached = null;
  const token = async () => {
    if (cached) return cached;   // the app keeps an ID token for 50 minutes
    const r = await call("auth.refreshToken", `${AUTH}/securetoken.googleapis.com/v1/token?key=${KEY}`,
      { body: { grant_type: "refresh_token", refresh_token: refresh } });
    refresh = r.json.refresh_token || refresh; cached = r.json.id_token || null; return cached || session.idToken;
  };
  const top = (tok, collection, field, path = "", limit = 10) => call(`fs.leaderboard(${collection})`, `${DOCS}${path}:runQuery`,
    { token: tok, body: { structuredQuery: { from: [{ collectionId: collection }], orderBy: [{ field: { fieldPath: field }, direction: "DESCENDING" }], limit } } });

  // Opens Games: the hub reads today's board.
  await top(await token(), "scores", "points", `/days/${today}`, 5);
  // Five answers, a few seconds of thinking each (compressed), score posted after every one.
  let total = 0, correct = 0;
  for (let q = 1; q <= 5; q++) {
    await sleep(200 + Math.random() * 1500);
    const right = Math.random() < 0.55, secs = Math.random() * 25;
    total += points(right, secs); if (right) correct++;
    const tok = await token();
    const f = { name: str(name), points: int(total), correct: int(correct), answered: int(q), updated: ts() };
    await call("fs.write score", `${DOCS}/days/${today}/scores/${uid}?${mask(f)}`, { method: "PATCH", token: tok, body: { fields: f } });
    if (q < 5) continue;   // all-time total: once, when the round is finished
    const pl = await call("fs.read player", `${DOCS}/players/${uid}`, { method: "GET", token: tok, okStatus: [404] });
    const prev = pl.json.fields || {};
    const lastDay = Number(prev.lastDay?.integerValue ?? -1), lastPts = Number(prev.lastPoints?.integerValue ?? 0), tot = Number(prev.total?.integerValue ?? 0);
    const g = { name: str(name), total: int((lastDay === today ? tot - lastPts : tot) + total), lastDay: int(today), lastPoints: int(total), updated: ts() };
    await call("fs.write player", `${DOCS}/players/${uid}?${mask(g)}`, { method: "PATCH", token: tok, body: { fields: g } });
  }
  expected[uid] = { name, total };
  // 1 in 20 tries to cheat: must be rejected by the rules.
  if (i % 20 === 7) {
    const f = { name: str(name), points: int(9999), correct: int(5), answered: int(5), updated: ts() };
    await call("fs.cheat (should be denied)", `${DOCS}/days/${today}/scores/${uid}?${mask(f)}`, { method: "PATCH", token: await token(), body: { fields: f }, expect: "denied" });
  }
  // Finished: refresh the board and open "See all" (Today and All time).
  const tok = await token();
  await top(tok, "scores", "points", `/days/${today}`, 5);
  if (Math.random() < 0.5) {   // about half open "See all"
    await top(tok, "scores", "points", `/days/${today}`, 10);
    await top(tok, "players", "total", "", 10);
  }
}

const pct = (a, p) => a[Math.min(a.length - 1, Math.floor(a.length * p))];
let release; const start = new Promise(r => (release = r));
const runs = Array.from({ length: USERS }, (_, i) => player(i, start).catch(e => note("crash", 0, false, e.message)));
const t0 = performance.now(); release(); await Promise.all(runs);
const secs = (performance.now() - t0) / 1000;
console.log(`\n${USERS} players, all starting at the same instant · finished in ${secs.toFixed(1)} s\n`);
console.log("operation".padEnd(30), "requests".padStart(8), "failed".padStart(7), "median".padStart(8), "p95".padStart(8), "p99".padStart(8));
let reqs = 0;
for (const [op, s] of Object.entries(stats)) {
  const t = s.t.sort((a, b) => a - b); reqs += s.n;
  console.log(op.padEnd(30), String(s.n).padStart(8), String(s.fail).padStart(7), (pct(t, .5) | 0) + " ms".padStart(0), "".padStart(1), String(pct(t, .95) | 0).padStart(6) + " ms", String(pct(t, .99) | 0).padStart(6) + " ms");
}
console.log(`\n${reqs} requests · ${(reqs / secs).toFixed(0)} a second on average`);
console.log(Object.keys(errors).length ? "Errors (each try counted): " + JSON.stringify(errors, null, 1) : "Errors: none");
console.log(`Firestore use: ${reads} reads and ${writes} writes in total = ${(reads / USERS).toFixed(1)} reads and ${(writes / USERS).toFixed(1)} writes a player`);

// Check what was stored, as the database owner (bypasses rules).
const all = async (path, coll) => {
  const r = await fetch(`${DOCS}${path}:runQuery`, { method: "POST", headers: { "Content-Type": "application/json", Authorization: "Bearer owner" },
    body: JSON.stringify({ structuredQuery: { from: [{ collectionId: coll }] } }) });
  return (await r.json()).filter(x => x.document).map(x => x.document);
};
const scores = await all(`/days/${today}`, "scores"), players = await all("", "players");
let wrong = 0, cheats = 0;
for (const d of scores) {
  const uid = d.name.split("/").pop(), p = Number(d.fields.points.integerValue);
  if (p > 750) cheats++;
  if (expected[uid] && expected[uid].total !== p) wrong++;
}
let wrongTotals = 0;
for (const d of players) { const uid = d.name.split("/").pop(); if (expected[uid] && Number(d.fields.total.integerValue) !== expected[uid].total) wrongTotals++; }
console.log(`\nStored: ${scores.length} scores today, ${players.length} all-time totals (expected ${Object.keys(expected).length})`);
console.log(`Wrong scores: ${wrong} · wrong all-time totals: ${wrongTotals} · cheated scores that got through: ${cheats}`);
