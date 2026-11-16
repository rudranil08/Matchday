// The News feed, written from licensed match data instead of copied articles:
// results with scorers, the next fixtures, and new injuries. Every line is a fact from the data.
const DAY = 86_400_000;

const ordinal = (n) => {
  const s = ["th", "st", "nd", "rd"];
  const v = n % 100;
  return n + (s[(v - 20) % 10] || s[v] || s[0]);
};

const surname = (name) => String(name).trim().split(/\s+/).slice(-1)[0];

function scorerLine(goals, team) {
  const mine = goals.filter((g) => g.teamID === team.id);
  if (!mine.length) return null;
  // "Saka 23', 67'" when a player scores twice.
  const byPlayer = new Map();
  for (const g of mine) {
    const who = surname(g.player) + (g.ownGoal ? " (og)" : "") + (g.penalty ? " (pen)" : "");
    byPlayer.set(who, [...(byPlayer.get(who) ?? []), `${g.minute}'`]);
  }
  return `${team.short}: ` + [...byPlayer].map(([who, mins]) => `${who} ${mins.join(", ")}`).join(", ");
}

function standing(table, team) {
  const row = table.find((r) => r.team.id === team.id);
  return row ? { rank: row.rank, points: row.points } : null;
}

export function buildFeed({ table = [], injuries = [], fixtures = [], now = Date.now() }) {
  const stories = [];

  // Results from the last eight days.
  for (const f of fixtures) {
    if (f.status !== "finished") continue;
    const kickoff = Date.parse(f.kickoff);
    if (!(now - kickoff < 8 * DAY)) continue;
    const { home, away, homeGoals: hg, awayGoals: ag } = f;
    const lines = [scorerLine(f.goals, home), scorerLine(f.goals, away)].filter(Boolean);
    const winner = hg > ag ? home : ag > hg ? away : null;
    const after = winner ? standing(table, winner) : null;
    const description = [
      lines.length ? lines.join(" · ") + "." : "No goals.",
      winner && after ? `${winner.short} are ${ordinal(after.rank)} on ${after.points} points.` : null,
      !winner ? "Honours even." : null,
    ].filter(Boolean).join(" ");
    stories.push({
      id: `result-${f.id}`,
      headline: `${home.short} ${hg}–${ag} ${away.short}`,
      description,
      published: new Date(Math.min(now, kickoff + 115 * 60_000)).toISOString(),
      image: null,
      url: null,
      kickoff: f.kickoff,
      teamIDs: [home.id, away.id],
      athletes: [...new Set(f.goals.map((g) => g.player))],
      tag: "Result",
    });
  }

  // The next week's fixtures, with where both sides stand.
  for (const f of fixtures) {
    if (f.status !== "upcoming") continue;
    const kickoff = Date.parse(f.kickoff);
    if (!(kickoff > now && kickoff - now < 7 * DAY)) continue;
    const h = standing(table, f.home);
    const a = standing(table, f.away);
    const description = h && a
      ? `${f.home.short} (${ordinal(h.rank)}, ${h.points} pts) host ${f.away.short} (${ordinal(a.rank)}, ${a.points} pts).`
      : `${f.home.short} host ${f.away.short}.`;
    stories.push({
      id: `preview-${f.id}`,
      headline: `${f.home.short} v ${f.away.short}`,
      description,
      // Shows up in the feed three days before kick-off.
      published: new Date(Math.min(now, kickoff - 3 * DAY)).toISOString(),
      image: null,
      url: null,
      kickoff: f.kickoff,
      teamIDs: [f.home.id, f.away.id],
      athletes: [],
      tag: "Preview",
    });
  }

  // Injuries that started in the last ten days.
  for (const i of injuries) {
    const since = i.since ? Date.parse(i.since) : NaN;
    if (!(now - since < 10 * DAY) || !i.club) continue;
    const specific = i.reason && !/^(injured|injury|unknown)$/i.test(i.reason);
    const headline = i.status === "Doubtful"
      ? `${i.name} a doubt for ${i.club.short}`
      : specific ? `${i.name} out with ${i.reason.toLowerCase()}` : `${i.name} out injured`;
    stories.push({
      id: `injury-${i.playerID}-${i.since.slice(0, 10)}`,
      headline,
      description: `${i.club.short} · ${i.returns}.`,
      published: new Date(Math.min(now, since)).toISOString(),
      image: null,
      url: null,
      kickoff: null,
      teamIDs: [i.club.id],
      athletes: [i.name],
      tag: "Injury",
    });
  }

  const seen = new Set();
  return stories
    .filter((s) => !seen.has(s.id) && seen.add(s.id))
    .sort((a, b) => Date.parse(b.published) - Date.parse(a.published));
}
