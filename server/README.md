# Matchday API

A small server between the app and the football data provider (Sportmonks). It keeps the
provider key off the iPhone, caches every response so the number of provider calls doesn't grow
with the number of users, and returns JSON already in the app's shapes.

Until a Sportmonks key is added it serves **sample data**: a real snapshot of tables, players
and injuries from October 2026, with generated results and fixtures. The app shows a
"Sample data" label while that's the case.

## Run it on your Mac

```bash
cd server
npm run dev        # http://localhost:8787  (Node 18 or later, no packages to install)
npm test           # 11 tests
```

Debug builds of the app use `http://localhost:8787`, which the iOS Simulator can reach.

## Endpoints

| Path | What | Cached for |
|---|---|---|
| `/v1/health` | mode (`live` or `sample`) | – |
| `/v1/{league}/table` | league table | 5 min |
| `/v1/{league}/players` | every player with a Form v2 score (see below) | 6 h |
| `/v1/{league}/injuries` | injured and suspended players | 3 h |
| `/v1/{league}/feed` | News: results, fixtures, new injuries | built from the above (fixtures 30 min) |

`league` is `pl`, `laliga`, `bundesliga` or `ligue1`. Each response is
`{ mode, league, updated, stale, data }`. If Sportmonks fails, the last good copy (up to a day old)
is served with `stale: true`.

## Adding the Sportmonks key

1. Sign up for the Starter plan and choose the Premier League, LaLiga, Bundesliga and Ligue 1.
2. Create `server/.dev.vars` (it's git-ignored) containing:
   ```
   SPORTMONKS_TOKEN=your-key
   ```
3. Run `npm run probe` (and `npm run probe laliga`, `bundesliga`, `ligue1`). It calls the real API,
   saves the responses to `test/real/` and lists anything that doesn't map cleanly. The mappings
   follow Sportmonks' documentation but haven't seen a real response yet, so this is the check.
4. `npm run dev` now serves live data.

## Putting it online (Cloudflare Workers, free plan)

```bash
npx wrangler login
npx wrangler secret put SPORTMONKS_TOKEN
npx wrangler deploy
```

Wrangler prints the address (e.g. `https://matchday-api.<you>.workers.dev`). Put it in
`Shared/ServerConfig.swift` as the release address before building for the App Store.

## Form score v2 (`src/form.js`)

Built from every finished match's line-ups and per-player stats:

- **Compared within the position.** Keepers on saves, clean sheets and goals against; defenders on
  defensive actions, duels won, goals against and going forward; midfielders on goals and assists,
  chances created, passing and winning the ball; forwards on goals, assists, shots on target and
  chances created. Each is a percentile against the league's players in that position.
- **Per 90 minutes**, so substitutes aren't punished for short appearances.
- **Recent games count:** the last five matches count as much as the whole season.
- **Playing time is confidence, not points:** score = confidence × rating + (1 − confidence) × 50,
  where confidence = minutes ÷ (minutes + 270). A player with few minutes stays near 50; playing
  every week doesn't earn points, it just makes the score more certain.
- The app applies the injury cut on top (doubtful × 0.75, out × 0.4).

In sample mode the match-by-match stats are generated from the snapshot's season totals, and each
club gets a sample keeper and four sample defenders (named as such). `npm run probe` checks that the
real line-ups carry positions, minutes, tackles and saves.

## Club names, codes and colours

`src/clubs-data.js` holds Matchday's 76 clubs: display names, three-letter codes, colours and the
other names providers use for them. Provider teams are matched to it by name within their league.
A club that isn't on the list (a newly promoted side, say) still works: it gets its provider name,
a code made from its initials and the app's neutral colour. Add it to the list to give it colours.

No crests are sent: the data licence doesn't cover club logos, so the app shows club-colour badges.
