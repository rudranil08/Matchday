// Sportmonks Football API v3: calls plus the mapping into Matchday's shapes.
// Field names and type ids follow Sportmonks' v3 documentation. Once the real key is in,
// run `npm run probe` to save real responses and re-check these mappings (see README).
import { makeTeam } from "./clubs.js";
import { rateLeague } from "./form.js";
import { LEAGUES, staticZone } from "./leagues.js";

const BASE = "https://api.sportmonks.com/v3/football";
const DAY = 86_400_000;

// Standing details, by type id with the developer name as a fallback.
const STAT = {
  played: [129, "OVERALL_MATCHES"],
  won: [130, "OVERALL_WINS"],
  drawn: [131, "OVERALL_DRAWS"],
  lost: [132, "OVERALL_LOST"],
  scored: [133, "OVERALL_SCORED", "OVERALL_GOALS"],
  conceded: [134, "OVERALL_CONCEDED"],
  goalDifference: [179, "GOAL_DIFFERENCE", "OVERALL_GOAL_DIFFERENCE"],
};
const TOPSCORER = { goals: [208, "GOAL_TOPSCORER"], assists: [209, "ASSIST_TOPSCORER"] };
const APPEARANCES = [321, "APPEARANCES"];
const GOAL_EVENTS = { goal: [14, "GOAL"], ownGoal: [15, "OWNGOAL", "OWN_GOAL"], penalty: [16, "PENALTY"] };
const FINISHED = new Set(["FT", "AET", "FT_PEN", "AWARDED"]);
// Per-player match statistics in line-ups (type id, developer name).
const PLAYER_STAT = {
  minutes: [119, "MINUTES_PLAYED"], goals: [52, "GOALS"], assists: [79, "ASSISTS"], shotsOnTarget: [86, "SHOTS_ON_TARGET"],
  keyPasses: [117, "KEY_PASSES"], tackles: [78, "TACKLES"], interceptions: [100, "INTERCEPTIONS"], clearances: [101, "CLEARANCES"],
  duels: [105, "TOTAL_DUELS"], duelsWon: [106, "DUELS_WON"], passes: [80, "PASSES"], passesAccurate: [116, "ACCURATE_PASSES"], saves: [57, "SAVES"],
};
const POSITION = { 24: "GK", 25: "DEF", 26: "MID", 27: "FWD" };
const STARTER = 11;
const UPCOMING = new Set(["NS", "TBA"]);

const typeIs = (item, [id, ...names]) =>
  item?.type_id === id || names.includes(item?.type?.developer_name) || names.includes(item?.type?.code?.toUpperCase?.());

function detail(details, spec) {
  const d = (details ?? []).find((x) => typeIs(x, spec));
  const v = d?.value;
  return typeof v === "object" && v !== null ? (v.total ?? v.all ?? null) : (v ?? null);
}

const playerName = (p) => p?.display_name ?? p?.common_name ?? p?.name ?? "Unknown player";
const teamOf = (participant, league) =>
  makeTeam({ id: participant?.id, name: participant?.name, shortCode: participant?.short_code }, league);

function kickoffISO(f) {
  if (f.starting_at_timestamp) return new Date(f.starting_at_timestamp * 1000).toISOString();
  return new Date(String(f.starting_at).replace(" ", "T") + "Z").toISOString();
}

function stateOf(f) {
  const s = f.state?.developer_name ?? f.state?.short_name ?? f.state?.state ?? "";
  if (FINISHED.has(s)) return "finished";
  if (UPCOMING.has(s)) return "upcoming";
  if (/INPLAY|HT|BREAK|EXTRA|PEN_BREAK|LIVE/.test(s)) return "live";
  return "other"; // postponed, cancelled, abandoned
}

const zoneFromRule = (s) => {
  const text = `${s.rule?.type?.name ?? ""} ${s.rule?.type?.developer_name ?? ""}`.toLowerCase();
  if (!text.trim()) return undefined;
  if (text.includes("conference")) return "uecl";
  if (text.includes("champions")) return "ucl";
  if (text.includes("europa")) return "uel";
  if (text.includes("releg")) return "relegation";
  return null;
};

const formatGD = (n) => (n > 0 ? `+${n}` : String(n ?? 0));
const dayMonth = (iso) => new Date(iso + "T12:00:00Z").toLocaleDateString("en-GB", { day: "numeric", month: "short", timeZone: "UTC" });

// MARK: mapping (pure: tested with saved responses)

export function normaliseStandings(raw, league) {
  const rows = (raw?.data ?? []).flatMap((s) => (Array.isArray(s.standings) ? s.standings : [s]));
  return rows
    .map((s) => {
      const d = (spec) => detail(s.details, spec);
      const scored = d(STAT.scored);
      const conceded = d(STAT.conceded);
      const gd = d(STAT.goalDifference) ?? (scored != null && conceded != null ? scored - conceded : 0);
      const rank = s.position;
      const ruled = zoneFromRule(s);
      return {
        team: teamOf(s.participant ?? { id: s.participant_id }, league),
        rank,
        played: d(STAT.played) ?? 0,
        won: d(STAT.won) ?? 0,
        drawn: d(STAT.drawn) ?? 0,
        lost: d(STAT.lost) ?? 0,
        goalDifference: formatGD(gd),
        points: s.points ?? 0,
        zone: ruled === undefined ? staticZone(league, rank) : ruled,
      };
    })
    .sort((a, b) => a.rank - b.rank);
}

export function normaliseTopscorers(raw, league, table = []) {
  const played = new Map(table.map((r) => [r.team.id, r.played]));
  const byPlayer = new Map();
  for (const t of raw?.data ?? []) {
    const id = String(t.player_id ?? t.player?.id);
    const team = teamOf(t.participant ?? { id: t.participant_id }, league);
    const apps = (t.player?.statistics ?? []).map((st) => detail(st.details, APPEARANCES)).find((v) => v != null);
    const prev = byPlayer.get(id) ?? { id, name: playerName(t.player), team, apps: 0, goals: 0, assists: 0 };
    if (typeIs(t, TOPSCORER.goals)) prev.goals = Math.max(prev.goals, t.total ?? 0);
    if (typeIs(t, TOPSCORER.assists)) prev.assists = Math.max(prev.assists, t.total ?? 0);
    // No appearance count? Use the team's games played, so Form Score still works.
    prev.apps = Math.max(prev.apps, apps ?? played.get(team.id) ?? Math.max(prev.goals, prev.assists));
    byPlayer.set(id, prev);
  }
  return [...byPlayer.values()];
}

export function normaliseSidelined(raw, league, now = Date.now()) {
  const today = new Date(now).toISOString().slice(0, 10);
  const list = [];
  for (const team of raw?.data ?? []) {
    const club = teamOf(team, league);
    for (const s of team.sidelined ?? []) {
      if (s.completed || (s.end_date && s.end_date < today)) continue;
      const reasonName = s.type?.name ?? (s.category === "suspension" ? "Suspended" : "Injured");
      const soon = s.end_date && Date.parse(s.end_date) - now <= 3 * DAY;
      const doubtful = /doubt|questionable/i.test(reasonName) || soon;
      list.push({
        playerID: s.player_id ?? s.player?.id,
        name: playerName(s.player),
        team: club.short,
        club,
        reason: reasonName,
        status: doubtful ? "Doubtful" : "Out",
        returns: s.end_date ? `Expected back ${dayMonth(s.end_date)}` : "Return date unknown",
        since: s.start_date ? new Date(s.start_date + "T12:00:00Z").toISOString() : null,
      });
    }
  }
  return list.sort((a, b) => (a.status === b.status ? a.team.localeCompare(b.team) : a.status === "Out" ? -1 : 1));
}

export function normaliseFixtures(raw, league) {
  return (raw?.data ?? []).map((f) => {
    const parts = f.participants ?? [];
    const homeP = parts.find((p) => p.meta?.location === "home") ?? parts[0];
    const awayP = parts.find((p) => p.meta?.location === "away") ?? parts[1];
    const home = teamOf(homeP, league);
    const away = teamOf(awayP, league);
    const current = (side) => {
      const list = (f.scores ?? []).filter((s) => s.score?.participant === side);
      return (list.find((s) => s.description === "CURRENT") ?? list.at(-1))?.score?.goals ?? null;
    };
    const goals = (f.events ?? [])
      .filter((e) => typeIs(e, GOAL_EVENTS.goal) || typeIs(e, GOAL_EVENTS.ownGoal) || typeIs(e, GOAL_EVENTS.penalty))
      .map((e) => {
        const own = typeIs(e, GOAL_EVENTS.ownGoal);
        // An own goal counts for the other side.
        const scorerTeam = String(e.participant_id) === home.id ? home : away;
        const forTeam = own ? (scorerTeam === home ? away : home) : scorerTeam;
        return { teamID: forTeam.id, player: e.player_name ?? playerName(e.player), minute: (e.minute ?? 0) + (e.extra_minute ?? 0),
                 ownGoal: own, penalty: typeIs(e, GOAL_EVENTS.penalty) };
      })
      .sort((a, b) => a.minute - b.minute);
    return { id: String(f.id), kickoff: kickoffISO(f), status: stateOf(f), home, away,
             homeGoals: current("home"), awayGoals: current("away"), goals };
  });
}

/** One record per player per finished match, for Form v2 (see form.js). */
export function normaliseLineups(raw, league) {
  const records = [];
  for (const f of raw?.data ?? []) {
    if (stateOf(f) !== "finished") continue;
    const sides = new Map((f.participants ?? []).map((p) => [String(p.id), { team: teamOf(p, league), location: p.meta?.location }]));
    const goalsFor = (location) => {
      const list = (f.scores ?? []).filter((s) => s.score?.participant === location);
      return (list.find((s) => s.description === "CURRENT") ?? list.at(-1))?.score?.goals ?? 0;
    };
    const date = kickoffISO(f);
    for (const l of f.lineups ?? []) {
      const side = sides.get(String(l.team_id));
      if (!side) continue;
      const stat = (spec) => {
        const d = (l.details ?? []).find((x) => typeIs(x, spec));
        const v = d?.data?.value ?? d?.value;
        return typeof v === "number" ? v : Number(v) || 0;
      };
      const minutes = stat(PLAYER_STAT.minutes) || (l.type_id === STARTER && !(l.details ?? []).length ? 90 : 0);
      if (!minutes) continue;
      const record = { playerId: String(l.player_id), name: l.player_name ?? playerName(l.player), team: side.team, date, minutes,
                       position: POSITION[l.position_id] ?? POSITION[l.player?.position_id] ?? null,
                       conceded: goalsFor(side.location === "home" ? "away" : "home") };
      for (const [key, spec] of Object.entries(PLAYER_STAT)) if (key !== "minutes") record[key] = stat(spec);
      records.push(record);
    }
  }
  return records;
}

// MARK: calls

export function sportmonks(token, fetchImpl = fetch) {
  async function get(path, params = {}) {
    const url = new URL(`${BASE}/${path}`);
    for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
    const res = await fetchImpl(url, { headers: { Authorization: token, Accept: "application/json" } });
    if (!res.ok) throw new Error(`Sportmonks ${res.status} for ${path}`);
    return res.json();
  }

  /** Follows pagination (at most 10 pages) and joins the `data` arrays. */
  async function getAll(path, params = {}) {
    const data = [];
    for (let page = 1; page <= 10; page++) {
      const body = await get(path, { ...params, per_page: 50, page });
      data.push(...(body.data ?? []));
      if (!body.pagination?.has_more) break;
    }
    return { data };
  }

  /** The current season's id (and start date, for Form v2's match history). */
  async function season(league) {
    const body = await get(`leagues/${LEAGUES[league].sportmonks}`, { include: "currentSeason" });
    const s = body.data?.currentseason ?? body.data?.currentSeason ?? body.data?.current_season;
    if (!s?.id) throw new Error(`No current season for ${league}`);
    return { id: s.id, start: s.starting_at ?? null };
  }

  return {
    mode: "live",
    season,
    async seasonID(league) {
      return (await season(league)).id;
    },
    async table(league, sid) {
      return normaliseStandings(await get(`standings/seasons/${sid}`, { include: "participant;details.type;rule.type" }), league);
    },
    /**
     * Form v2: every finished match this season with its line-ups and per-player stats, rated by
     * position. Fetched in 90-day windows (the date-range endpoint's limit). Cached for 6 hours.
     */
    async players(league, sid, table, { start, now = Date.now() } = {}) {
      const from = Date.parse(start ?? "") || now - 120 * DAY;
      const data = [];
      for (let a = from; a < now; a += 90 * DAY) {
        const b = Math.min(a + 89 * DAY, now);
        const raw = await getAll(`fixtures/between/${new Date(a).toISOString().slice(0, 10)}/${new Date(b).toISOString().slice(0, 10)}`, {
          include: "participants;scores;state;lineups.details.type",
          filters: `fixtureLeagues:${LEAGUES[league].sportmonks};lineupDetailTypes:${Object.values(PLAYER_STAT).map(([id]) => id).join(",")}`,
        });
        data.push(...raw.data);
      }
      const rated = rateLeague(normaliseLineups({ data }, league));
      // No line-up stats on this plan? Fall back to the top scorers list (the old Form score runs on it).
      if (rated.length) return rated;
      const top = await getAll(`topscorers/seasons/${sid}`, { include: "player;participant;type", filters: "seasonTopscorerTypes:208,209" });
      return normaliseTopscorers(top, league, table);
    },
    async injuries(league, sid, now = Date.now()) {
      return normaliseSidelined(await get(`teams/seasons/${sid}`, { include: "sidelined.player;sidelined.type" }), league, now);
    },
    async fixtures(league, now = Date.now()) {
      const from = new Date(now - 8 * DAY).toISOString().slice(0, 10);
      const to = new Date(now + 7 * DAY).toISOString().slice(0, 10);
      const raw = await getAll(`fixtures/between/${from}/${to}`, {
        include: "participants;scores;events.type;state",
        filters: `fixtureLeagues:${LEAGUES[league].sportmonks}`,
      });
      return normaliseFixtures(raw, league);
    },
  };
}
