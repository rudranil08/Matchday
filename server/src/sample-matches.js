// Sample mode only: match-by-match player stats, generated from the real season totals in the
// snapshot (goals, assists, appearances), so Form v2 can run before the Sportmonks key arrives.
// The snapshot only lists scorers and assisters, so each club also gets a sample keeper and four
// sample defenders, named as such. Everything is deterministic: same day, same numbers.
import { SAMPLE } from "./sample-data.js";

const DAY = 86_400_000;
const WEEK = 7 * DAY;

function hash(text) {
  let h = 0x811c9dc5;
  for (const ch of String(text)) { h ^= ch.charCodeAt(0); h = Math.imul(h, 0x01000193) >>> 0; }
  return h;
}
const rnd = (seed) => (hash(seed) % 10_000) / 10_000; // 0–1
const around = (mean, seed, spread = 0.6) => Math.max(0, Math.round(mean * (1 - spread / 2 + spread * rnd(seed))));

function saturdayBefore(t) {
  const d = new Date(t);
  d.setUTCHours(15, 0, 0, 0);
  while (d.getUTCDay() !== 6 || d.getTime() > t) d.setTime(d.getTime() - DAY);
  return d.getTime();
}

/** Spreads `count` events over the matches played, early, late or evenly (each player has a trend). */
function spread(count, games, seed) {
  const trend = hash(`${seed}-trend`) % 3; // 0 even, 1 early-season, 2 recent
  const weight = (i) => (trend === 0 ? 1 : trend === 1 ? games.length - i : i + 1);
  const total = games.reduce((s, _, i) => s + weight(i), 0);
  const out = games.map(() => 0);
  for (let k = 0; k < count; k++) {
    let pick = rnd(`${seed}-${k}`) * total;
    for (let i = 0; i < games.length; i++) { pick -= weight(i); if (pick <= 0) { out[i] += 1; break; } }
  }
  return out;
}

function statsFor(position, q, seed) {
  const s = (name, mean, spreadBy) => around(mean, `${seed}-${name}`, spreadBy);
  switch (position) {
    case "GK": return { saves: s("sv", 1.2 + 3.2 * q), duels: 0, duelsWon: 0, passes: s("p", 28), passesAccurate: s("pa", 28 * (0.6 + 0.25 * q), 0.2) };
    case "DEF": {
      const duels = s("d", 8);
      return { tackles: s("t", 1 + 2.5 * q), interceptions: s("i", 0.6 + 1.6 * q), clearances: s("c", 1.5 + 4 * q),
               duels, duelsWon: Math.min(duels, around(duels * (0.35 + 0.35 * q), `${seed}-dw`, 0.3)), passes: s("p", 48), passesAccurate: s("pa", 48 * (0.74 + 0.16 * q), 0.15) };
    }
    case "MID": {
      const duels = s("d", 9);
      return { tackles: s("t", 0.8 + 2 * q), interceptions: s("i", 0.4 + 1.2 * q), clearances: s("c", 0.5), keyPasses: s("k", 0.4 + 2.2 * q),
               shotsOnTarget: s("so", 0.2 + 0.8 * q), duels, duelsWon: Math.min(duels, around(duels * (0.38 + 0.25 * q), `${seed}-dw`, 0.3)),
               passes: s("p", 52), passesAccurate: s("pa", 52 * (0.76 + 0.14 * q), 0.15) };
    }
    default: {
      const duels = s("d", 11);
      return { tackles: s("t", 0.4 + 0.6 * q), interceptions: s("i", 0.2), clearances: s("c", 0.3), keyPasses: s("k", 0.3 + 1.6 * q),
               shotsOnTarget: s("so", 0.5 + 1.8 * q), duels, duelsWon: Math.min(duels, around(duels * (0.3 + 0.2 * q), `${seed}-dw`, 0.3)),
               passes: s("p", 24), passesAccurate: s("pa", 24 * (0.65 + 0.15 * q), 0.2) };
    }
  }
}

/** Every player's matches for one league, ready for `rateLeague`. */
export function sampleMatches(league, now = Date.now()) {
  const { table, players } = SAMPLE[league];
  const last = saturdayBefore(now - 2 * 3600 * 1000);
  const records = [];
  const teams = table.length;

  for (const row of table) {
    const team = row.team;
    const n = row.played;
    const dates = Array.from({ length: n }, (_, g) => new Date(last - (n - 1 - g) * WEEK).toISOString());
    // Better teams concede less: 0.6 a game at the top, 2 at the bottom.
    const concededMean = 0.6 + (1.4 * (row.rank - 1)) / Math.max(1, teams - 1);
    const conceded = dates.map((_, g) => Math.round(concededMean * 2 * rnd(`${team.id}-${g}-ga`) ** 1.3));

    const add = (id, name, position, q, games, goals, assists, minutesFor) => {
      games.forEach((g, k) => {
        const minutes = minutesFor(g);
        records.push({ playerId: id, name, team, position, date: dates[g], minutes, conceded: conceded[g],
                       goals: goals[k] ?? 0, assists: assists[k] ?? 0, keyPasses: 0, shotsOnTarget: 0, tackles: 0, interceptions: 0, clearances: 0, saves: 0,
                       ...statsFor(position, q, `${id}-${g}`) });
      });
    };

    // Real scorers and assisters from the snapshot.
    for (const p of players.filter((x) => x.team.id === team.id)) {
      const apps = Math.min(Math.max(p.apps, 1), n);
      const order = [...Array(n).keys()].sort((a, b) => rnd(`${p.id}-${a}`) - rnd(`${p.id}-${b}`));
      const games = order.slice(0, apps).sort((a, b) => a - b);
      // The snapshot has no positions: rarely involved in goals → defender, more assists → midfielder.
      const involvement = (p.goals + p.assists) / apps;
      const position = involvement < 0.34 ? "DEF" : p.assists > p.goals ? "MID" : "FWD";
      const q = Math.min(1, 0.2 + ((p.goals + p.assists) / apps) * 0.55 + 0.15 * rnd(`${p.id}-q`));
      const sub = rnd(`${p.id}-sub`) < 0.25;
      add(p.id, p.name, position, q, games, spread(p.goals, games, `${p.id}-g`), spread(p.assists, games, `${p.id}-a`),
          (g) => (sub && rnd(`${p.id}-${g}-m`) < 0.5 ? 15 + Math.round(25 * rnd(`${p.id}-${g}-mm`)) : 70 + Math.round(20 * rnd(`${p.id}-${g}-mm`))));
    }

    // Sample keeper and defenders: they play every game, whatever their quality.
    const all = [...Array(n).keys()];
    add(`s-${team.id}-gk`, `${team.short} keeper (sample)`, "GK", rnd(`${team.id}-gkq`), all, [], [], () => 90);
    ["A", "B", "C", "D"].forEach((letter, i) => {
      const id = `s-${team.id}-d${letter}`;
      const games = i === 3 ? all.filter((g) => g % 3 !== 1) : all; // one rotates
      const assists = spread(Math.round(2 * rnd(`${id}-as`)), games, `${id}-a`);
      add(id, `${team.short} defender ${letter} (sample)`, "DEF", rnd(`${id}-q`), games, [], assists, () => 90);
    });
  }
  return records;
}
