// The four leagues Matchday covers, with their Sportmonks ids.
// `zones` are the usual end-of-season places, used only when Sportmonks sends no standing rule.
export const LEAGUES = {
  pl: {
    name: "Premier League",
    sportmonks: 8,
    zones: { ucl: [1, 4], uel: [5, 5], uecl: [6, 6], relegation: [18, 20] },
  },
  laliga: {
    name: "LaLiga",
    sportmonks: 564,
    zones: { ucl: [1, 4], uel: [5, 6], uecl: [7, 7], relegation: [18, 20] },
  },
  bundesliga: {
    name: "Bundesliga",
    sportmonks: 82,
    zones: { ucl: [1, 4], uel: [5, 5], uecl: [6, 6], relegation: [17, 18] },
  },
  ligue1: {
    name: "Ligue 1",
    sportmonks: 301,
    zones: { ucl: [1, 3], uel: [4, 4], uecl: [5, 5], relegation: [17, 18] },
  },
};

export const isLeague = (id) => Object.hasOwn(LEAGUES, id);

/** Zone for a table position from the static rules above. */
export function staticZone(league, rank) {
  for (const [zone, [from, to]] of Object.entries(LEAGUES[league].zones)) {
    if (rank >= from && rank <= to) return zone;
  }
  return null;
}
