// Matchday API: a Cloudflare Worker between the app and the football data provider.
//
//   GET /v1/health
//   GET /v1/{league}/table | players | injuries | feed      league = pl, laliga, bundesliga, ligue1
//
// Every response is { mode, league, updated, stale, data }. `mode` is "live" with a Sportmonks
// key (the SPORTMONKS_TOKEN secret) and "sample" without one. The key never leaves this server.
import { cached } from "./cache.js";
import { buildFeed } from "./feed.js";
import { isLeague, LEAGUES } from "./leagues.js";
import { sample } from "./sample.js";
import { sportmonks } from "./sportmonks.js";

const MIN = 60;
const TTL = { season: 12 * 60 * MIN, table: 5 * MIN, players: 6 * 60 * MIN, injuries: 3 * 60 * MIN, fixtures: 30 * MIN };

function json(status, body, extra = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": status === 200 ? "public, max-age=60" : "no-store", ...extra },
  });
}

/** Loads one kind of data for a league through the cache. Returns { value, at, stale }. */
async function load(kind, league, p, now) {
  const key = (k) => `${p.mode}:${k}:${league}`;
  if (p.mode === "sample") {
    if (kind === "injuries" || kind === "fixtures" || kind === "players") return cached(key(kind), TTL[kind], () => p[kind](league, now), now);
    return cached(key(kind), TTL[kind], () => p[kind](league), now);
  }
  const season = (await cached(key("season"), TTL.season, () => p.season(league), now)).value;
  const sid = season.id;
  switch (kind) {
    case "table": return cached(key("table"), TTL.table, () => p.table(league, sid), now);
    case "players": {
      const table = (await load("table", league, p, now)).value;
      return cached(key("players"), TTL.players, () => p.players(league, sid, table, { start: season.start, now }), now);
    }
    case "injuries": return cached(key("injuries"), TTL.injuries, () => p.injuries(league, sid, now), now);
    case "fixtures": return cached(key("fixtures"), TTL.fixtures, () => p.fixtures(league, now), now);
  }
  throw new Error(`Unknown data: ${kind}`);
}

async function feed(league, p, now) {
  const [table, injuries, fixtures] = await Promise.all(["table", "injuries", "fixtures"].map((k) => load(k, league, p, now)));
  return {
    value: buildFeed({ table: table.value, injuries: injuries.value, fixtures: fixtures.value, now }),
    at: Math.min(table.at, injuries.at, fixtures.at),
    stale: table.stale || injuries.stale || fixtures.stale,
  };
}

export async function handle(request, env = {}, { fetchImpl = fetch, now = Date.now() } = {}) {
  if (request.method !== "GET") return json(405, { error: "Only GET is supported." }, { allow: "GET" });
  const p = env.SPORTMONKS_TOKEN ? sportmonks(env.SPORTMONKS_TOKEN, fetchImpl) : sample;
  const parts = new URL(request.url).pathname.split("/").filter(Boolean);

  if (parts.length === 2 && parts[0] === "v1" && parts[1] === "health") {
    return json(200, { ok: true, mode: p.mode, leagues: Object.keys(LEAGUES) });
  }
  const [version, league, kind] = parts;
  if (version !== "v1" || parts.length !== 3 || !isLeague(league) || !["table", "players", "injuries", "feed"].includes(kind)) {
    return json(404, { error: "Not found." });
  }
  try {
    const result = kind === "feed" ? await feed(league, p, now) : await load(kind, league, p, now);
    return json(200, { mode: p.mode, league, updated: new Date(result.at).toISOString(), stale: result.stale, data: result.value });
  } catch (error) {
    console.error(`${league}/${kind}:`, error?.message ?? error);
    return json(502, { error: "The football data provider isn't answering. Try again shortly." });
  }
}

export default {
  fetch: (request, env) => handle(request, env),
};
