import { test } from "node:test";
import assert from "node:assert/strict";
import { matchClub, makeTeam } from "../src/clubs.js";
import { normaliseStandings, normaliseTopscorers, normaliseSidelined, normaliseFixtures, normaliseLineups, sportmonks } from "../src/sportmonks.js";
import { buildFeed } from "../src/feed.js";
import { handle } from "../src/index.js";
import { clearMemory } from "../src/cache.js";
import * as raw from "./fixtures.js";

const NOW = Date.parse("2026-10-22T12:00:00Z");
const get = (path, env = {}, opts = {}) => handle(new Request(`http://localhost${path}`), env, { now: NOW, ...opts });

test("provider club names map to Matchday's clubs", () => {
  const cases = [
    ["FC Bayern München", "bundesliga", "Bayern"], ["1. FC Köln", "bundesliga", "Cologne"],
    ["Borussia Mönchengladbach", "bundesliga", "Gladbach"], ["Bayer 04 Leverkusen", "bundesliga", "Leverkusen"],
    ["Paris Saint-Germain", "ligue1", "PSG"], ["Olympique Lyonnais", "ligue1", "Lyon"], ["LOSC Lille", "ligue1", "Lille"],
    ["Brighton & Hove Albion", "pl", "Brighton"], ["Tottenham Hotspur", "pl", "Spurs"], ["Nottingham Forest", "pl", "Nottm Forest"],
    ["Athletic Club", "laliga", "Athletic"], ["Real Betis Balompié", "laliga", "Betis"], ["Club Atlético de Madrid", "laliga", "Atlético"],
  ];
  for (const [name, league, short] of cases) assert.equal(matchClub(name, league)?.short, short, name);
  assert.equal(matchClub("Some Town United", "pl"), null);
  assert.equal(matchClub("Arsenal", "laliga"), null, "only matches inside the league");
});

test("teams carry Matchday's colours and the old ESPN id", () => {
  const t = makeTeam({ id: 19, name: "Arsenal", shortCode: "ARS" }, "pl");
  assert.deepEqual([t.id, t.short, t.color, t.code, t.crest], ["19", "Arsenal", "e20520", "ARS", null]);
  assert.deepEqual(t.aliases, ["359"]);
  const unknown = makeTeam({ id: 5, name: "Some Town United" }, "pl");
  assert.equal(unknown.code, "STU");
  assert.equal(unknown.color, null);
});

test("standings map to table rows, in order, with zones", () => {
  const rows = normaliseStandings(raw.standings, "pl");
  assert.deepEqual(rows.map((r) => r.team.short), ["Man City", "Arsenal", "Nottm Forest"]);
  const [city, arsenal, forest] = rows;
  assert.deepEqual([arsenal.played, arsenal.won, arsenal.drawn, arsenal.lost, arsenal.points], [7, 6, 0, 1, 18]);
  assert.equal(arsenal.goalDifference, "+6", "worked out from goals for and against");
  assert.equal(city.goalDifference, "+12");
  assert.equal(arsenal.zone, "ucl");
  assert.equal(city.zone, "ucl", "no rule: falls back to the usual places");
  assert.equal(forest.zone, "relegation");
  assert.equal(forest.goalDifference, "-11");
});

test("top scorers merge goals and assists per player", () => {
  const table = normaliseStandings(raw.standings, "pl");
  const players = normaliseTopscorers(raw.topscorers, "pl", table);
  const saka = players.find((p) => p.name === "Bukayo Saka");
  assert.deepEqual([saka.goals, saka.assists, saka.apps], [6, 4, 7]);
  const haaland = players.find((p) => p.id === "2");
  assert.equal(haaland.apps, 7, "no appearances sent: uses the team's games played");
});

test("sidelined players become the injury list", () => {
  const list = normaliseSidelined(raw.sidelined, "pl", NOW);
  assert.equal(list.length, 3, "finished injuries are dropped");
  const saka = list.find((i) => i.name === "Bukayo Saka");
  assert.deepEqual([saka.status, saka.reason, saka.returns, saka.team], ["Out", "Hamstring Injury", "Expected back 12 Nov", "Arsenal"]);
  assert.equal(list.find((i) => i.name === "Nearly Back").status, "Doubtful");
  assert.equal(list.find((i) => i.name === "Red Card").reason, "Suspended");
  assert.equal(list.at(-1).status, "Doubtful", "out first, then doubtful");
});

test("fixtures map with scores, scorers and own goals credited correctly", () => {
  const [done, next] = normaliseFixtures(raw.fixtures, "pl");
  assert.deepEqual([done.status, done.homeGoals, done.awayGoals, done.home.short, done.away.short], ["finished", 2, 1, "Arsenal", "Nottm Forest"]);
  assert.equal(done.goals.length, 3, "a booking is not a goal");
  const og = done.goals.find((g) => g.ownGoal);
  assert.equal(og.teamID, done.home.id, "an own goal counts for the other side");
  assert.equal(done.goals.at(-1).minute, 90);
  assert.equal(next.status, "upcoming");
  assert.equal(next.kickoff, "2026-10-25T16:30:00.000Z");
});

test("line-ups become one record per player per finished match", () => {
  const records = normaliseLineups(raw.lineups, "pl");
  assert.equal(records.length, 3, "unused subs and unplayed matches are skipped");
  const saka = records.find((r) => r.name === "Bukayo Saka");
  assert.deepEqual([saka.position, saka.minutes, saka.goals, saka.shotsOnTarget, saka.keyPasses, saka.conceded], ["FWD", 90, 1, 3, 2, 0]);
  const saliba = records.find((r) => r.name === "William Saliba");
  assert.deepEqual([saliba.position, saliba.tackles, saliba.interceptions, saliba.duels, saliba.duelsWon], ["DEF", 3, 2, 8, 6]);
  const sels = records.find((r) => r.name === "Matz Sels");
  assert.deepEqual([sels.position, sels.saves, sels.conceded, sels.team.short], ["GK", 5, 2, "Nottm Forest"]);
});

test("the feed reads like news and only uses facts", () => {
  const table = normaliseStandings(raw.standings, "pl");
  const feed = buildFeed({ table, injuries: normaliseSidelined(raw.sidelined, "pl", NOW), fixtures: normaliseFixtures(raw.fixtures, "pl"), now: NOW });
  const result = feed.find((s) => s.tag === "Result");
  assert.equal(result.headline, "Arsenal 2–1 Nottm Forest");
  assert.match(result.description, /Arsenal: Saka 54', Murillo \(og\) 70'/);
  assert.match(result.description, /Arsenal are 2nd on 18 points\./);
  const preview = feed.find((s) => s.tag === "Preview");
  assert.equal(preview.headline, "Man City v Arsenal");
  assert.match(preview.description, /Man City \(1st, 21 pts\) host Arsenal \(2nd, 18 pts\)/);
  assert.ok(feed.some((s) => s.headline === "Bukayo Saka out with hamstring injury"));
  assert.ok(feed.every((s) => s.url === null && s.image === null), "no links to anyone else's articles");
  for (let i = 1; i < feed.length; i++) assert.ok(feed[i - 1].published >= feed[i].published, "newest first");
});

test("sample mode serves every league and kind", async () => {
  clearMemory();
  for (const league of ["pl", "laliga", "bundesliga", "ligue1"]) {
    for (const kind of ["table", "players", "injuries", "feed"]) {
      const res = await get(`/v1/${league}/${kind}`);
      assert.equal(res.status, 200, `${league}/${kind}`);
      const body = await res.json();
      assert.equal(body.mode, "sample");
      assert.ok(body.data.length > 0, `${league}/${kind} has data`);
    }
  }
  const players = (await (await get("/v1/pl/players")).json()).data;
  for (const pos of ["GK", "DEF", "MID", "FWD"]) assert.ok(players.some((p) => p.position === pos), `sample has ${pos}s`);
  assert.ok(players.every((p) => p.form && p.form.parts.length >= 3 && p.minutes > 0), "every player has a v2 form score");
  const table = (await (await get("/v1/pl/table")).json()).data;
  for (const r of table) {
    assert.equal(r.team.crest, null, "no crests are sent");
    assert.ok(r.team.code && r.team.color, `${r.team.short} has a code and colour`);
  }
  const injuries = (await (await get("/v1/ligue1/injuries")).json()).data;
  assert.ok(injuries.every((i) => i.club), "every injured player's club is recognised");
});

test("bad requests are refused", async () => {
  assert.equal((await get("/v1/seriea/table")).status, 404);
  assert.equal((await get("/v1/pl/odds")).status, 404);
  assert.equal((await handle(new Request("http://localhost/v1/pl/table", { method: "POST" }), {})).status, 405);
});

test("live mode calls Sportmonks with the key in a header, caches, and falls back when it fails", async () => {
  clearMemory();
  const calls = [];
  let down = false;
  const fake = async (url) => {
    calls.push(url);
    if (down) return new Response("", { status: 500 });
    const path = new URL(url).pathname;
    const body = path.includes("/leagues/") ? { data: { currentseason: { id: 777 } } }
      : path.includes("/standings/") ? raw.standings : { data: [] };
    return new Response(JSON.stringify(body), { status: 200 });
  };
  const env = { SPORTMONKS_TOKEN: "test-token" };
  const first = await (await get("/v1/pl/table", env, { fetchImpl: fake })).json();
  assert.equal(first.mode, "live");
  assert.equal(first.data.length, 3);
  assert.ok(calls.every((u) => !String(u).includes("test-token")), "the key is never in a URL");
  assert.ok(calls.some((u) => String(u).includes("/standings/seasons/777")));
  const before = calls.length;
  await get("/v1/pl/table", env, { fetchImpl: fake });
  assert.equal(calls.length, before, "a second request inside 5 minutes is served from the cache");
  down = true;
  const later = await (await get("/v1/pl/table", env, { fetchImpl: fake, now: NOW + 10 * 60_000 })).json();
  assert.equal(later.stale, true, "provider down: the last good table is served, marked stale");
  assert.equal(later.data.length, 3);
  const nothing = await get("/v1/laliga/table", env, { fetchImpl: fake });
  assert.equal(nothing.status, 502, "provider down and nothing cached: a clear error");
});

test("the Sportmonks client sends the key as a header", async () => {
  let seen;
  const client = sportmonks("abc", async (url, init) => { seen = { url: String(url), auth: init.headers.Authorization };
    return new Response(JSON.stringify({ data: { currentseason: { id: 1 } } })); });
  assert.equal(await client.seasonID("pl"), 1);
  assert.deepEqual(await client.season("pl"), { id: 1, start: null });
  assert.equal(seen.auth, "abc");
  assert.match(seen.url, /\/leagues\/8\?include=currentSeason/);
});
