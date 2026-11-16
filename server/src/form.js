// Form score v2. Each player is compared with others in the same position, on what that position
// actually does, per 90 minutes, with the last five games counting as much as the whole season.
// Playing time doesn't earn points: it decides how sure the score is. A player with few minutes is
// pulled towards the middle (50) until there's enough to judge, so neither a lucky cameo nor a
// manager's favourite who plays every week gets a score he hasn't earned.

export const POSITIONS = ["GK", "DEF", "MID", "FWD"];
const RECENT_GAMES = 5;
const RECENT_WEIGHT = 0.5;      // the last five games count for half
const CONFIDENCE_MINUTES = 270; // after 270 minutes (three full games) the score is half data, half average
const QUALIFY_MINUTES = 180;    // players with fewer minutes don't set the bar for others

const one = (n) => (Math.round(n * 10) / 10).toString();
const pct = (n) => `${Math.round(n * 100)}%`;

/** Totals for a set of match records. */
function totals(rows) {
  const t = { minutes: 0, apps: 0, goals: 0, assists: 0, shotsOnTarget: 0, keyPasses: 0, tackles: 0, interceptions: 0,
    clearances: 0, duels: 0, duelsWon: 0, passes: 0, passesAccurate: 0, saves: 0, concededOnPitch: 0, full: 0, cleanSheets: 0 };
  for (const r of rows) {
    if (!(r.minutes > 0)) continue;
    t.apps += 1;
    t.minutes += r.minutes;
    for (const k of ["goals", "assists", "shotsOnTarget", "keyPasses", "tackles", "interceptions", "clearances", "duels", "duelsWon", "passes", "passesAccurate", "saves"]) {
      t[k] += r[k] ?? 0;
    }
    // Goals the team conceded while he was on the pitch (shared out by minutes played).
    t.concededOnPitch += (r.conceded ?? 0) * Math.min(r.minutes, 90) / 90;
    if (r.minutes >= 60) {
      t.full += 1;
      if ((r.conceded ?? 0) === 0) t.cleanSheets += 1;
    }
  }
  return t;
}

const per90 = (x, t) => (t.minutes > 0 ? (x / t.minutes) * 90 : null);
const ratio = (a, b) => (b > 0 ? a / b : null);

// What each position is judged on. `value` reads a totals object; `low` means lower is better.
const METRICS = {
  GK: [
    { label: "Shot stopping", weight: 0.35, value: (t) => per90(t.saves, t), note: (v) => `${one(v)} saves a game` },
    { label: "Clean sheets", weight: 0.35, value: (t) => ratio(t.cleanSheets, t.full), note: (v, t) => `${t.cleanSheets} in ${t.full} full games` },
    { label: "Goals against", weight: 0.3, low: true, value: (t) => per90(t.concededOnPitch, t), note: (v) => `Team concedes ${one(v)} a game with him in goal` },
  ],
  DEF: [
    { label: "Defending", weight: 0.3, value: (t) => per90(t.tackles + t.interceptions + t.clearances, t), note: (v) => `${one(v)} defensive actions a game` },
    { label: "Duels", weight: 0.25, value: (t) => ratio(t.duelsWon, t.duels), note: (v) => `Wins ${pct(v)} of his duels` },
    { label: "Goals against", weight: 0.3, low: true, value: (t) => per90(t.concededOnPitch, t), note: (v) => `Team concedes ${one(v)} a game with him on` },
    { label: "Going forward", weight: 0.15, value: (t) => per90(t.goals + t.assists, t), note: (v, t) => `${t.goals} goals, ${t.assists} assists` },
  ],
  MID: [
    { label: "Goals and assists", weight: 0.3, value: (t) => per90(t.goals + t.assists, t), note: (v, t) => `${t.goals} goals, ${t.assists} assists` },
    { label: "Creating chances", weight: 0.25, value: (t) => per90(t.keyPasses, t), note: (v) => `${one(v)} chances created a game` },
    { label: "Passing", weight: 0.2, value: (t) => ratio(t.passesAccurate, t.passes), note: (v) => `${pct(v)} of passes find a teammate` },
    { label: "Winning the ball", weight: 0.25, value: (t) => per90(t.tackles + t.interceptions, t), note: (v) => `${one(v)} tackles and interceptions a game` },
  ],
  FWD: [
    { label: "Goals", weight: 0.45, value: (t) => per90(t.goals, t), note: (v, t) => `${t.goals} goals, ${one(v)} a game` },
    { label: "Assists", weight: 0.15, value: (t) => per90(t.assists, t), note: (v, t) => `${t.assists} assists` },
    { label: "Shots on target", weight: 0.25, value: (t) => per90(t.shotsOnTarget, t), note: (v) => `${one(v)} shots on target a game` },
    { label: "Creating chances", weight: 0.15, value: (t) => per90(t.keyPasses, t), note: (v) => `${one(v)} chances created a game` },
  ],
};

/** Season value blended with the last five games, when he's played enough of them to count. */
function blended(metric, season, recent) {
  const s = metric.value(season);
  const r = recent.minutes >= 90 ? metric.value(recent) : null;
  if (s == null) return null;
  return r == null ? s : (1 - RECENT_WEIGHT) * s + RECENT_WEIGHT * r;
}

/** Share of the pool this value beats (ties count half). 0–1. */
function percentile(value, pool, low) {
  if (!pool.length) return 0.5;
  let below = 0, equal = 0;
  for (const p of pool) {
    if (p === value) equal += 1;
    else if (low ? p > value : p < value) below += 1;
  }
  return (below + equal / 2) / pool.length;
}

const verdict = (p) => (p >= 0.85 ? "Elite" : p >= 0.65 ? "Strong" : p >= 0.35 ? "Average" : "Weak");

function mostCommon(list) {
  const counts = new Map();
  for (const x of list) if (x) counts.set(x, (counts.get(x) ?? 0) + 1);
  return [...counts].sort((a, b) => b[1] - a[1])[0]?.[0] ?? null;
}

/**
 * Rates every player in a league from match-by-match records:
 * { playerId, name, team, position (GK|DEF|MID|FWD), date, minutes, goals, assists, shotsOnTarget,
 *   keyPasses, tackles, interceptions, clearances, duels, duelsWon, passes, passesAccurate, saves, conceded }
 * Returns the app's PlayerStat shape plus `position`, `minutes` and `form`.
 */
export function rateLeague(records) {
  const byPlayer = new Map();
  for (const r of records) {
    if (!byPlayer.has(r.playerId)) byPlayer.set(r.playerId, []);
    byPlayer.get(r.playerId).push(r);
  }

  const players = [];
  for (const [id, rows] of byPlayer) {
    const played = rows.filter((r) => r.minutes > 0).sort((a, b) => Date.parse(a.date) - Date.parse(b.date));
    if (!played.length) continue;
    const position = mostCommon(played.map((r) => r.position)) ?? "MID";
    const season = totals(played);
    const recent = totals(played.slice(-RECENT_GAMES));
    players.push({ id: String(id), rows: played, position, season, recent, last: played.at(-1) });
  }

  // Each metric's values across the position, from players with enough minutes to set the bar.
  const pools = {};
  for (const pos of POSITIONS) {
    const group = players.filter((p) => p.position === pos);
    const qualified = group.filter((p) => p.season.minutes >= QUALIFY_MINUTES);
    const base = qualified.length >= 5 ? qualified : group;
    pools[pos] = METRICS[pos].map((m) => base.map((p) => blended(m, p.season, p.recent)).filter((v) => v != null));
  }

  return players.map((p) => {
    const metrics = METRICS[p.position];
    let sum = 0, weights = 0;
    const parts = [];
    metrics.forEach((m, i) => {
      const v = blended(m, p.season, p.recent);
      if (v == null) return;
      const share = percentile(v, pools[p.position][i], m.low);
      sum += share * m.weight;
      weights += m.weight;
      parts.push({ label: m.label, note: m.note(v, p.season), verdict: verdict(share), value: Math.round(share * 100) / 100 });
    });
    const raw = weights > 0 ? sum / weights : 0.5;
    const confidence = p.season.minutes / (p.season.minutes + CONFIDENCE_MINUTES);
    const score = Math.round(100 * (confidence * raw + (1 - confidence) * 0.5));
    return {
      id: p.id,
      name: p.last.name,
      team: p.last.team,
      apps: p.season.apps,
      goals: p.season.goals,
      assists: p.season.assists,
      position: p.position,
      minutes: p.season.minutes,
      form: { score, confidence: Math.round(confidence * 100) / 100, parts },
    };
  }).sort((a, b) => b.form.score - a.form.score);
}
