// Run once the Sportmonks key is in server/.dev.vars:   npm run probe [league]
// Saves real responses to test/real/ (git-ignored: it's licensed data) and checks the mappings,
// printing a warning for anything that looks wrong (e.g. a stat that came back as all zeros).
import { mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { LEAGUES } from "../src/leagues.js";
import { sportmonks, normaliseStandings, normaliseTopscorers, normaliseSidelined, normaliseFixtures } from "../src/sportmonks.js";

const vars = new URL("../.dev.vars", import.meta.url);
const token = process.env.SPORTMONKS_TOKEN
  ?? (existsSync(vars) ? readFileSync(vars, "utf8").match(/SPORTMONKS_TOKEN\s*=\s*"?([^"\n]+)"?/)?.[1] : undefined);
if (!token) {
  console.error("No key. Put SPORTMONKS_TOKEN=... in server/.dev.vars first.");
  process.exit(1);
}
const league = process.argv[2] ?? "pl";
if (!LEAGUES[league]) { console.error(`Unknown league ${league}`); process.exit(1); }

const out = new URL("../test/real/", import.meta.url);
mkdirSync(out, { recursive: true });
const saved = {};
const recordingFetch = async (url, init) => {
  const res = await fetch(url, init);
  const text = await res.text();
  const name = new URL(url).pathname.split("/").slice(3, 5).join("-") || "root";
  saved[name] = (saved[name] ?? 0) + 1;
  writeFileSync(new URL(`${league}-${name}-${saved[name]}.json`, out), text);
  return new Response(text, { status: res.status, headers: res.headers });
};

const warn = [];
const check = (ok, message) => { if (!ok) warn.push(message); };
const sm = sportmonks(token, recordingFetch);

const season = await sm.season(league);
const sid = season.id;
console.log(`${LEAGUES[league].name}: current season ${sid}, started ${season.start ?? "unknown"}`);

const table = await sm.table(league, sid);
console.log(`Table: ${table.length} rows. Top: ${table.slice(0, 3).map((r) => `${r.rank}. ${r.team.short} ${r.points} pts (P${r.played} GD ${r.goalDifference})`).join(" · ")}`);
check(table.length >= 18, "table has fewer than 18 rows");
check(table.some((r) => r.played > 0), "games played is 0 for everyone: check the standing detail type ids (STAT.played)");
check(table.every((r) => r.won + r.drawn + r.lost === r.played), "won + drawn + lost ≠ played: check the W/D/L type ids");
check(table.every((r) => r.team.color), `clubs not matched to Matchday's list: ${table.filter((r) => !r.team.color).map((r) => r.team.name).join(", ")}`);
check(table.some((r) => r.zone === "ucl") && table.some((r) => r.zone === "relegation"), "no Champions League or relegation zone found");

const players = await sm.players(league, sid, table, { start: season.start });
const top = [...players].sort((a, b) => b.goals - a.goals).slice(0, 3);
console.log(`Players: ${players.length}. Top scorers: ${top.map((p) => `${p.name} ${p.goals}g ${p.assists}a ${p.apps} apps`).join(" · ")}`);
check(players.some((p) => p.goals > 0), "no goals: check the GOALS line-up stat (52)");
check(players.some((p) => p.assists > 0), "no assists: check the ASSISTS line-up stat (79)");
// Form v2 needs per-player match stats and positions from the line-ups.
check(players.every((p) => p.form), "no Form v2 scores: the plan may not include line-up stats (fell back to top scorers)");
const pos = Object.fromEntries(["GK", "DEF", "MID", "FWD"].map((k) => [k, players.filter((p) => p.position === k)]));
console.log(`Form v2 positions: ${Object.entries(pos).map(([k, v]) => `${k} ${v.length}`).join(", ")}`);
check(players.filter((p) => !p.position).length === 0, "some players have no position: check position_id in line-ups");
check(pos.DEF?.some((p) => p.form?.parts.some((x) => x.label === "Defending" && !/^0\.0 /.test(x.note))), "defenders show no tackles or interceptions: check stat ids 78/100/101");
check(pos.GK?.some((p) => p.form?.parts.some((x) => x.label === "Shot stopping" && !/^0\.0 /.test(x.note))), "keepers show no saves: check stat id 57");
check(players.some((p) => p.minutes >= 450), "nobody has 450+ minutes: check MINUTES_PLAYED (119)");
for (const [k, v] of Object.entries(pos)) if (v.length) console.log(`  best ${k}: ${v.slice(0, 3).map((p) => `${p.name} ${p.form.score}`).join(", ")}`);

const injuries = await sm.injuries(league, sid);
console.log(`Injuries: ${injuries.length}. e.g. ${injuries.slice(0, 3).map((i) => `${i.name} (${i.team}) ${i.status}, ${i.returns}`).join(" · ")}`);
check(injuries.length > 0, "no injuries at all: check the sidelined include");

const fixtures = await sm.fixtures(league);
const done = fixtures.filter((f) => f.status === "finished");
console.log(`Fixtures: ${fixtures.length} (${done.length} finished). e.g. ${done.slice(0, 2).map((f) => `${f.home.short} ${f.homeGoals}–${f.awayGoals} ${f.away.short} [${f.goals.map((g) => `${g.player} ${g.minute}'`).join(", ")}]`).join(" · ")}`);
check(done.every((f) => f.goals.length === f.homeGoals + f.awayGoals), "scorer count ≠ score in some matches: check the goal event type ids");

console.log(`\nSaved raw responses to server/test/real/.`);
if (warn.length) {
  console.log(`\n${warn.length} thing(s) to check:\n` + warn.map((w) => `  • ${w}`).join("\n"));
  process.exit(2);
}
console.log("Everything maps cleanly.");
// Keep the normalisers referenced so the saved files can be re-checked by hand.
void normaliseStandings; void normaliseTopscorers; void normaliseSidelined; void normaliseFixtures;
