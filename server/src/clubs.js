// Club identity: Matchday shows its own club names, three-letter codes and colours, whatever
// the data provider calls a club. Providers send names like "FC Bayern München" or
// "1. FC Köln", so clubs are matched by a normalised name within their league.
import { CLUBS } from "./clubs-data.js";

// Words that say nothing about which club it is.
const FILLER = new Set(["fc", "cf", "afc", "sc", "ac", "ud", "rcd", "sv", "ssv", "club", "de", "the"]);

export function normalise(name) {
  return String(name ?? "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9 ]+/g, " ")
    .split(/\s+/)
    .filter((w) => w && !FILLER.has(w) && !/^\d+$/.test(w))
    .join(" ");
}

const byLeague = new Map();
for (const club of CLUBS) {
  const names = new Set([club.name, club.short, ...club.aliases].map(normalise).filter(Boolean));
  const entry = { ...club, names };
  if (!byLeague.has(club.league)) byLeague.set(club.league, []);
  byLeague.get(club.league).push(entry);
}

const tokens = (s) => new Set(s.split(" ").filter(Boolean));

/** The Matchday club for a provider's team name, or null if it isn't one we know. */
export function matchClub(name, league) {
  const key = normalise(name);
  if (!key) return null;
  const clubs = league ? byLeague.get(league) ?? [] : CLUBS.map((c) => byLeague.get(c.league)).flat();
  const exact = clubs.find((c) => c.names.has(key));
  if (exact) return exact;
  // Close enough: most of the words agree (e.g. "Brighton Hove Albion" vs "Brighton and Hove Albion").
  let best = null;
  let bestScore = 0;
  const a = tokens(key);
  for (const c of clubs) {
    for (const n of c.names) {
      const b = tokens(n);
      const shared = [...a].filter((w) => b.has(w)).length;
      const score = shared / Math.max(a.size, b.size);
      if (score > bestScore) { bestScore = score; best = c; }
    }
  }
  return bestScore >= 0.6 ? best : null;
}

/** A short code for a club we don't know (a newly promoted side, say): "Some Town United" → "STU". */
export function deriveCode(name) {
  const words = normalise(name).split(" ").filter(Boolean);
  if (words.length >= 2) return words.slice(0, 3).map((w) => w[0]).join("").toUpperCase();
  return (words[0] ?? "?").slice(0, 3).toUpperCase();
}

/**
 * The Team object the app expects. `id` is the provider's id; `aliases` carries the old
 * ESPN id so the app can carry a user's saved clubs over to the new ids.
 */
export function makeTeam({ id, name, shortCode }, league) {
  const club = matchClub(name, league);
  const providerID = String(id);
  return {
    id: providerID,
    name: club?.name ?? name ?? "Unknown club",
    short: club?.short ?? name ?? "Unknown",
    crest: null,
    color: club?.color ?? null,
    alt: club?.alt ?? null,
    league,
    code: club?.code ?? shortCode ?? deriveCode(name),
    aliases: club && club.espn !== providerID ? [club.espn] : [],
  };
}
