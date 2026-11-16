// Sample provider: used until a Sportmonks key is set. Real tables, players and injuries from an
// October 2026 snapshot; results and fixtures are generated from the table so the News feed has
// something to show. The app labels all of it "Sample data".
import { SAMPLE } from "./sample-data.js";
import { matchClub } from "./clubs.js";
import { rateLeague } from "./form.js";
import { sampleMatches } from "./sample-matches.js";

const DAY = 86_400_000;
const WEEK = 7 * DAY;

function hash(text) {
  let h = 0x811c9dc5;
  for (const ch of String(text)) { h ^= ch.charCodeAt(0); h = Math.imul(h, 0x01000193) >>> 0; }
  return h;
}

/** Saturday 15:00 UTC on or before `t`. */
function saturdayBefore(t) {
  const d = new Date(t);
  d.setUTCHours(15, 0, 0, 0);
  while (d.getUTCDay() !== 6 || d.getTime() > t) d.setTime(d.getTime() - DAY);
  return d.getTime();
}

/** Pairs for one round of a round robin (circle method), so each week brings new match-ups. */
function round(teams, week) {
  const list = [...teams];
  const fixed = list.shift();
  const r = week % list.length;
  const rotated = [...list.slice(r), ...list.slice(0, r)];
  const all = [fixed, ...rotated];
  const pairs = [];
  for (let i = 0; i < all.length / 2; i++) {
    const a = all[i];
    const b = all[all.length - 1 - i];
    pairs.push((week + i) % 2 ? [a, b] : [b, a]);
  }
  return pairs;
}

function scorers(league, team, count, seed) {
  const squad = SAMPLE[league].players.filter((p) => p.team.id === team.id).sort((a, b) => b.goals - a.goals);
  const goals = [];
  for (let i = 0; i < count; i++) {
    const h = hash(`${seed}-${team.id}-${i}`);
    const p = squad.length ? squad[h % Math.min(3, squad.length)] : null;
    goals.push({ teamID: team.id, player: p?.name ?? `${team.short} player`, minute: 4 + (h % 86), ownGoal: false, penalty: false });
  }
  return goals;
}

function fixtures(league, now) {
  const teams = SAMPLE[league].table.map((r) => r.team);
  const last = saturdayBefore(now - 2 * 3600 * 1000);
  const week = Math.floor(last / WEEK);
  const make = (start, w, finished) => round(teams, w).map(([home, away]) => {
    const id = `${league}-${w}-${home.id}-${away.id}`;
    const h = hash(id);
    const hg = finished ? h % 4 : null;
    const ag = finished ? (h >>> 4) % 3 : null;
    const goals = finished ? [...scorers(league, home, hg, id), ...scorers(league, away, ag, id)].sort((a, b) => a.minute - b.minute) : [];
    return { id, kickoff: new Date(start).toISOString(), status: finished ? "finished" : "upcoming", home, away, homeGoals: hg, awayGoals: ag, goals };
  });
  return [...make(last, week, true), ...make(last + WEEK, week + 1, false)];
}

export const sample = {
  mode: "sample",
  async table(league) {
    return SAMPLE[league].table;
  },
  /** Form v2 from generated match-by-match stats (see sample-matches.js). */
  async players(league, now = Date.now()) {
    return rateLeague(sampleMatches(league, now));
  },
  async injuries(league, now = Date.now()) {
    const teams = new Map(SAMPLE[league].table.map((r) => [r.team.id, r.team]));
    return SAMPLE[league].injuries.map((i) => {
      const club = matchClub(i.teamName, league);
      const team = club ? teams.get(club.espn) : null;
      // When each injury began isn't in the snapshot: spread them over the last few weeks.
      const since = new Date(now - (hash(`${i.playerID}`) % 28) * DAY).toISOString();
      return { playerID: i.playerID, name: i.name, team: team?.short ?? i.teamName, club: team ?? null,
               reason: i.reason, status: i.status, returns: i.returns, since };
    });
  },
  async fixtures(league, now = Date.now()) {
    return fixtures(league, now);
  },
};
