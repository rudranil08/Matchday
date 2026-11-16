import { test } from "node:test";
import assert from "node:assert/strict";
import { rateLeague } from "../src/form.js";

const team = (id) => ({ id, name: `Club ${id}`, short: `Club ${id}`, league: "pl", crest: null });

// One match record for a player. `q` (0–1) sets how good he is at his position's job.
function match(playerId, position, g, { q = 0.5, minutes = 90, conceded = 1, goals = 0, assists = 0 } = {}) {
  return {
    playerId, name: playerId, team: team("1"), position, minutes, goals, assists, conceded,
    date: new Date(Date.UTC(2026, 7, 1) + g * 7 * 86_400_000).toISOString(),
    shotsOnTarget: Math.round(3 * q), keyPasses: Math.round(3 * q), tackles: Math.round(1 + 4 * q), interceptions: Math.round(1 + 2 * q),
    clearances: Math.round(1 + 4 * q), duels: 10, duelsWon: Math.round(3 + 5 * q), passes: 50, passesAccurate: Math.round(35 + 13 * q), saves: Math.round(1 + 4 * q),
  };
}

// A league of defenders: eight average ones, a strong one and a poor one the manager never drops.
function defenders() {
  const rows = [];
  for (let g = 0; g < 9; g++) {
    for (let i = 0; i < 8; i++) rows.push(match(`avg${i}`, "DEF", g, { q: 0.4 + i * 0.03, conceded: 1 }));
    rows.push(match("rock", "DEF", g, { q: 0.95, conceded: g % 3 === 0 ? 1 : 0 }));
    rows.push(match("favourite", "DEF", g, { q: 0.05, conceded: 2 }));
  }
  return rows;
}

test("defenders are judged on defending, not on goals", () => {
  const rated = rateLeague(defenders());
  const rock = rated.find((p) => p.id === "rock");
  assert.ok(rock.form.score >= 75, `a dominant defender with no goals scores high (got ${rock.form.score})`);
  assert.equal(rock.goals, 0);
  assert.ok(rock.form.parts.some((p) => p.label === "Duels" && p.verdict === "Elite"));
});

test("playing every game doesn't rescue a poor player: it makes his low score more certain", () => {
  const rated = rateLeague(defenders());
  const favourite = rated.find((p) => p.id === "favourite");
  assert.equal(favourite.apps, 9, "he played every game");
  assert.ok(favourite.form.score <= 25, `but his score is low (got ${favourite.form.score})`);
  assert.ok(favourite.form.confidence >= 0.7, "and the score is a confident one");
  const defending = favourite.form.parts.filter((p) => p.label !== "Going forward"); // nobody in this league scores
  assert.ok(defending.every((p) => p.verdict === "Weak"), "weak at every part of defending");
});

test("a short cameo is pulled towards the middle instead of topping the list", () => {
  const rows = defenders();
  rows.push(match("cameo", "DEF", 8, { q: 1, minutes: 20, conceded: 0 }));
  const rated = rateLeague(rows);
  const cameo = rated.find((p) => p.id === "cameo");
  assert.ok(cameo.form.confidence < 0.1, "20 minutes is barely anything to judge");
  assert.ok(Math.abs(cameo.form.score - 50) <= 5, `so he sits near 50 (got ${cameo.form.score})`);
  assert.equal(rated[0].id, "rock", "the proven player stays on top");
});

test("rates are per 90 minutes, so a sub isn't punished for coming on late", () => {
  const rows = [];
  for (let g = 0; g < 8; g++) {
    for (let i = 0; i < 6; i++) rows.push(match(`f${i}`, "FWD", g, { q: 0.4, goals: g % 4 === 0 ? 1 : 0 }));
    // Same goals as the regulars, in a third of the minutes.
    rows.push(match("supersub", "FWD", g, { q: 0.4, minutes: 30, goals: g % 4 === 0 ? 1 : 0 }));
  }
  const rated = rateLeague(rows);
  const sub = rated.find((p) => p.id === "supersub");
  const regular = rated.find((p) => p.id === "f0");
  assert.ok(sub.form.parts.find((p) => p.label === "Goals").value > regular.form.parts.find((p) => p.label === "Goals").value);
});

test("recent form counts: the same season, scored late, beats scored early", () => {
  const rows = [];
  for (let g = 0; g < 10; g++) {
    for (let i = 0; i < 6; i++) rows.push(match(`f${i}`, "FWD", g, { q: 0.4, goals: g % 5 === 0 ? 1 : 0 }));
    rows.push(match("early", "FWD", g, { q: 0.4, goals: g < 4 ? 1 : 0 }));
    rows.push(match("late", "FWD", g, { q: 0.4, goals: g >= 6 ? 1 : 0 }));
  }
  const rated = rateLeague(rows);
  const early = rated.find((p) => p.id === "early");
  const late = rated.find((p) => p.id === "late");
  assert.equal(early.goals, late.goals, "same number of goals");
  assert.ok(late.form.score > early.form.score, `in-form player ranks higher (${late.form.score} vs ${early.form.score})`);
});

test("keepers are judged on saves and clean sheets", () => {
  const rows = [];
  for (let g = 0; g < 8; g++) {
    for (let i = 0; i < 6; i++) rows.push(match(`gk${i}`, "GK", g, { q: 0.4, conceded: 1 }));
    rows.push(match("wall", "GK", g, { q: 0.9, conceded: 0 }));
  }
  const wall = rateLeague(rows).find((p) => p.id === "wall");
  assert.ok(wall.form.score >= 75, `got ${wall.form.score}`);
  assert.deepEqual(wall.form.parts.map((p) => p.label), ["Shot stopping", "Clean sheets", "Goals against"]);
});
