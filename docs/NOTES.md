# Matchday: development notes

Native SwiftUI app for the Premier League, LaLiga, Bundesliga and Ligue 1: live tables, a news feed written from match data, a Form score that rates every player against his own position (per 90 minutes, recent games weighted, playing time as confidence), injuries, and a quiz. Club colours and club badges throughout.

## What's in 1.0.0

**App**
- News, Table, Form, Injuries and Games, with licensed data (Sportmonks, through Matchday's own server in `server/`) and pull to refresh
- Follow your club: its stories come first in News, it's starred and highlighted in Table and Form (press and hold a club in Table, or Settings › Your club)
- Search players and clubs across all four leagues
- Player sheet with a plain-language "Why 96" and a **Share card** (renders an image of the player's Form card)
- Share any story
- Offline: the last data is saved on the iPhone and shown with an "Offline" badge when there's no signal
- Fast on slow networks: 15-second timeouts (then the saved copy), compact JSON from Matchday's own server (cached there, so provider calls don't grow with users), long lists built lazily, and injuries for all leagues loaded side by side
- Daily quiz: every player gets their own five questions a day (seeded by their account), mixing 21 checked classic facts with questions built from today's live tables and stats. 100 points a right answer, up to 50 more for answering within 20 seconds. One scored round a day (saved on the iPhone, so it can't be replayed), plus unscored bonus rounds
- Games is a hub of three cards: today's quiz (your status and one button), today's leaderboard (top three and your place, See all), and the form duel, played right on the hub: two players face off, tap the one with the higher live Form score, both scores count up and the winner lights up in their club colour. The quiz plays full screen, one question at a time. The full leaderboard opens its own screen.
- Leaderboard: Today and All time, top 20, your row marked (Firestore, see below). Tested end to end: the rules reject 10 kinds of fake or bad scores (too many points, someone else's score, yesterday's board, extra fields, not signed in…)
- Haptics on quiz answers, duels, following a club and switching league or tab
- Dynamic Type (text scales with the iPhone's text-size setting), VoiceOver labels on rows, light and dark mode

**Newer iOS** (each falls back cleanly; the app still supports iOS 17)
- iOS 26+: **Catch me up** in News. Apple Intelligence writes three points about your club from the latest headlines, on the iPhone (FoundationModels, weak-linked). Hidden where Apple Intelligence isn't available.
- iOS 26+: the tab bar shrinks as you scroll, with your main club's table position above it. Tap it to open the table.
- iOS 27: swipe a club in the Table to follow it (swipe actions on custom rows).
- iOS 27: drag your leagues in Settings to reorder them. The top one is your main league.

**Speed and storage**
- Screens open on the last saved data at once, then refresh. Data under 5 minutes old isn't fetched again.
- Your leagues are fetched ahead of time when the app opens, when they change, and in iOS background refresh (`com.matchday.app.refresh`).
- Saved data is pruned automatically: anything over a week old, other leagues' data after a day, and a 20 MB cap. The image and HTTP cache is capped at 40 MB. Memory is released when iOS asks or the app goes to the background.
- Settings › Saved on this iPhone shows the size and has a Clear button.

**Widgets** (Home Screen and Lock Screen)
- League table: small (leader in club colour), medium (top 5), large (top 10), Lock Screen rectangular and inline. Configure the league and a club to highlight.
- Form leader: small (top player in club colour), medium (top 3), Lock Screen rectangular and inline. Configure the leagues.
- Tapping a widget opens the matching screen (`matchday://table?league=pl`, `matchday://form`).

**Siri and Shortcuts**
- "Who's top of the league in Matchday?" answers without opening the app
- "Show the table in Matchday", "Who's in form in Matchday", "Show football news in Matchday", "Play the Matchday quiz"

**League-first layout**
- Onboarding: pick your league (four cards with their current top three), then a club from that league only. Continue sweeps the club's colour across the screen into the home screen, whose header is already that colour.
- News and Form show your league only, in sections (News: Your club, Match reports, Transfers, Injuries; Form: In form, Top scorers, Top assists, Your club). Each shows three; More expands it in place.
- Table can still show any league. Change your league and club in Settings › Your league and club.
- Injuries from Sportmonks via the server: who's out, who's a doubt, and when they're expected back.
- News is written from match data: results with scorers, the next week's fixtures and new injuries. No one else's articles are copied or linked.

**Accounts and onboarding**
- Welcome screen on an interactive floodlit pitch: flick the ball, score for a "GOAL" flash and haptic; tilt the phone and the pitch responds (stays still with Reduce Motion on)
- Sign in or create an account with a username and password, or continue with Google
- Pick your club: league tabs, a grid of club badges (colours and a three-letter code; crests aren't covered by the data licence), and the screen takes the club's colour as you choose
- Passwords are never stored: each is a salted PBKDF2-SHA256 hash (310,000 rounds) in the Keychain, this device only. Show / hide toggle, 5 wrong tries locks sign-in for 30 seconds, and the screen is blurred in the app switcher
- Checker (highest) account: built into the app for testing; only its salt and hash ship in the app (`Matchday/Auth/AuthStore.swift`). Settings › Checker tools shows data-feed health, accounts on the device (usernames only) and resets. **Change its credentials before release.**

**Google sign-in setup**
1. Google Cloud Console › APIs & Services › Credentials › Create credentials › OAuth client ID › **iOS**, bundle ID `com.matchday.app`.
2. Paste the client ID (`…apps.googleusercontent.com`) into `Shared/Secrets.swift` › `googleClientID`.
3. That's it: sign-in runs in Apple's secure web sheet (PKCE), no SDK needed. Until it's set, the button explains what's missing.

**Staying signed in**
- Each account keeps its own leagues and clubs on the iPhone, so signing back in goes straight home. Only a new account picks teams.
- **Remember me** (sign-in screen and Settings › Account) keeps you signed in after closing the app and fills in your username. Off, Matchday asks again next launch.
- **New user mode** (checker only) affects only the checker account. Other accounts stay signed in.

**Email accounts and Forgot password (Firebase Authentication, free)**
With a key set, new accounts sign up with an email and verify it with a link. **Forgot password?** on the sign-in screen emails a reset link. Both links open Google's own pages, so they work on any device (phone or computer). After resetting, sign in with the new password. Google sends the emails, so no email server is needed.

Free (Spark) plan: 150 reset emails and 1,000 verification emails a day, 3,000 daily users. Each iPhone can also ask for at most 15 emails an hour.

1. https://console.firebase.google.com › **Add project** (Analytics not needed).
2. **Build › Authentication › Get started › Sign-in method › Email/Password › Enable** (leave "Email link" off).
3. **Project settings › General › Web API key** (starts with `AIza`): paste it into `firebaseAPIKey` in `Shared/Secrets.swift`. If no key shows, add a Web app on the same page first.
4. Recommended: **Project settings › General › Public-facing name** = "Matchday", so emails say Matchday. Authentication › Templates lets you edit the wording.
5. Recommended: Google Cloud Console › APIs & Services › Credentials › that API key › **Application restrictions: iOS apps**, bundle ID `com.matchday.app`. The app sends its bundle ID with every request.

Delete account removes the Firebase account too. A password reset signs the account out on other devices the next time they open the app. Without a key the app works as before (local username accounts), and Forgot password explains it isn't set up. Local username accounts, the checker, Google and Apple can't be reset by email.

**Games leaderboard (Cloud Firestore, same Firebase project, free)**
1. Firebase console › **Build › Firestore Database › Create database**. Production mode, any location.
2. Firestore › **Rules**: paste the contents of `firestore.rules` from this folder and **Publish**. Each player can only write their own score, only for today, and only up to 750 points (5 × 150).
3. **Authentication › Sign-in method › Anonymous › Enable**. Email accounts post scores as themselves. Username, checker, Google and Apple accounts get a private anonymous Firebase identity, kept in the Keychain.
4. Put your Firebase project ID in `firebaseProjectID` in `Shared/Secrets.swift`.

Free-plan budget: 50,000 reads and 20,000 writes a day. A player uses about 10 writes and 5 reads a round, plus 20 reads each time they open the board (kept for a minute). That's room for well over 1,000 players a day. Names shown are usernames, or a first name and initial: never emails.

**Privacy, age and content (compliance pass, 20 Oct 2026)**
- **Age gate.** Before any account, Matchday asks once for a month and year of birth: two blank wheels, no defaults, no hint about the "right" age. Only the result (13 or over, or under 13) is kept, in the Keychain, so reinstalling doesn't reset it. People who were already signed in are asked once (the checker account is exempt).
- **Under 13: guest mode.** No account, no email, no Sign in with Apple or Google, no Firebase ID, no leaderboard. The quiz, duel and every other tab work, and everything stays on the iPhone.
- **Legal pages.** Privacy Policy, Terms of Use and Copyright and Content, in `Matchday/Legal/LegalInfo.swift`, shown in the app (Settings › Legal, and the "By continuing you agree…" line at sign-up and on the welcome screen). Fill in `operatorName`, `contactEmail` and, once hosted, the URLs in that file. `python3 legal/build.py` builds matching web pages in `legal/`, with self-hosted fonts and no Google Fonts; host that folder and use the privacy URL in App Store Connect. The text is a draft: have a lawyer review it.
- **Deleting an account removes everything.** Leaderboard name and scores (every day since the board opened), the anonymous Firebase identity, the account itself, and data on the iPhone. If there's no signal it stops before deleting anything.
- **Names.** Usernames and leaderboard names go through a word filter (`Auth/NameFilter.swift`) that also blocks impersonation ("admin", "official"…). Press and hold a leaderboard name to **Report** it (filed in `reports/`, readable only in the Firebase console) or **Hide** it on your iPhone.
- **Removing names and repeat offenders.** In the Firebase console: delete the player's documents under `players/` and `days/{day}/scores/`; to ban them, add a document with their ID under `banned/`. The rules then stop them posting.
- **Rules.** `firestore.rules` now also allows players to delete their own records, blocks banned players, and accepts reports without letting anyone read them. **Paste it into Firestore › Rules › Publish again.** Tested on the emulator: 18 of 18 rule checks, plus the 1,000-player load test (no regressions).

**Sign in with Apple** is on the welcome screen (App Store guideline 4.8 requires it alongside Google). It needs a paid Apple Developer team: with automatic signing, Xcode adds the capability from `Matchday/Matchday.entitlements`. Free personal teams can't use it, so the button only works once you sign with a paid team. The app checks the Apple credential each time it opens and signs out if it was revoked in Settings › Apple ID.

## Tests

`ComplianceTests`: the age gate (13 and over, and under 13), guest mode Games, the legal pages, and Report and Hide on leaderboard names.

Run the suite on an **iOS 26** simulator as well as iOS 27. On iOS 26.5 the tab tour found a real freeze: a lazy list under the overlapping cards fell into an endless layout loop when scrolling back to News. Screens now use a regular stack on iOS 26 and the lazy one on iOS 27 (`ScreenStack` in `UI/Components.swift`), and the shrinking tab bar is limited to iOS 27.

`MatchdayUITests` (in the Matchday scheme, ⌘U) runs on a simulator. DEBUG-only launch flags sign in the checker with Arsenal and Barcelona, so no real account is needed.
- `NewFeatureTests`: swipe to follow (iOS 27), make main league (iOS 27), Catch me up (Apple Intelligence), the daily quiz, and the leaderboard end to end (needs Firestore and Anonymous sign-in on)
- `ReliabilityTests`: offline shows saved data on every tab, cold-launch time, and a tour of every tab and league
- `ChaosTests`: the app under an overloaded network (DEBUG flag `-uiTestChaos`: 20% timeouts, 10% dropped connections, 15% server errors, 10% garbage replies, up to 3 s delay on every request), starting with no saved data (`-uiTestFreshInstall`). One test uses every screen twice: all tabs, all leagues, pull to refresh, Search, Settings, a full quiz, the duel, the leaderboard, background and back. The other does 10 cold launches in a row. Both check the app is still running after every step.

Measured on an iPhone 17 Pro simulator (iOS 27.1, debug build):
- cold launch about 2.3 s
- 28–35 MB of memory per tab, levelling off at about 85 MB after every tab and league (peak 95 MB under the chaos test)
- no Thread Sanitizer warnings, and no crash reports from any test run, chaos included
- (Measured against the old ESPN and FotMob feeds; re-run once the Sportmonks key is in.)

### 1,000 players at once (`LoadTest/`)

`LoadTest/` runs 1,000 virtual players against Google's local Firebase emulators with the real `firestore.rules` (how to run: `LoadTest/README.md`). Every player starts at the same instant and follows the app's exact requests.
- **Before the fixes:** 1,000 players, 21,679 requests in 9.4 s. The stored data was always correct and every cheat was refused, but about 18% of sign-in requests were dropped under the burst. The app didn't retry, so 209 players never got a score posted. Each player also used about 80 Firestore reads, which would pass the free 50,000 a day at 1,000 players.
- **Fixed in the app:**
  - Leaderboard requests retry dropped connections and busy or server errors: 3 tries, with random spacing so 1,000 phones don't retry together.
  - The sign-in token is reused for 50 minutes instead of being refreshed for every request.
  - A network blip can no longer create a second anonymous identity, which would have put the same person on the board twice.
  - The all-time total is written once per round.
  - The Games screen reads 5 rows and the full board 10.
  - A score that didn't get through is posted again the next time Games opens.
- **After the fixes:** 1,000 players, 13,220 requests in 8.2 s. Every player finished, all 1,000 scores and 1,000 all-time totals were stored exactly right, and 50 of 50 cheat attempts were refused. Each player uses about 18 reads and 6 writes, so the free plan covers about 2,700 players a day.

Not load-tested on purpose:
- **Data server:** every phone calls Matchday's server, which caches Sportmonks' answers (tables 5 min, players 6 h, injuries 3 h), so provider calls stay flat however many people use the app. If Sportmonks fails, the last good copy is served. The chaos tests cover a slow or failing server.
- **The live Firebase project:** the emulators were used instead, to avoid using quota or leaving test data.

Firebase Auth allows 100 new accounts an hour from one IP address. 1,000 people signing up together on one shared Wi-Fi (an event, a school) would hit that limit. You can schedule a temporary increase in the Firebase console › Authentication › Settings.

## Run it

1. Open `Matchday.xcodeproj` (Xcode 16 or later).
2. Choose an iPhone simulator and press ⌘R. To try the widgets, press and hold the simulator's Home Screen › Edit › Add Widget › Matchday.

## Release checklist (App Store)

1. **Signing**: select the **Matchday** target › Signing & Capabilities › choose your Team. Do the same for **MatchdayWidget**. If `com.matchday.app` is taken, change both bundle IDs (the widget must stay `<app id>.widget`).
2. **Data server**: subscribe to Sportmonks Starter (Premier League, LaLiga, Bundesliga, Ligue 1), put the key in `server/.dev.vars`, run `npm run probe` in `server/`, then deploy to Cloudflare Workers and set the address in `Shared/ServerConfig.swift`. See `server/README.md`. Until then the server serves sample data and the app says so.
3. **Licence questions**: get Sportmonks' written answer on use in a published app, caching on your server, logos (the app shows badges, not crests) and attribution.
4. **App Store Connect**: create the app, set the age rating, privacy answers: Email Address, Name, User ID and Gameplay Content, linked to the user, for app functionality, not tracking. This matches `PrivacyInfo.xcprivacy`. Privacy policy URL: the hosted `legal/privacy.html`. Age rating: the leaderboard shows player-chosen names (user-generated content), screenshots, and a support URL.
5. **Archive**: Product › Archive › Distribute App › App Store Connect.

Already done: app icon, privacy manifest (app and widget), `ITSAppUsesNonExemptEncryption = NO` (no export-compliance question), version 1.0.0 (1), Sports category, portrait-only iPhone.

## Project layout

```
Matchday/                 the app
  MatchdayApp.swift       entry, tabs, app state (followed club, deep links)
  AppShortcuts.swift      Siri / Shortcuts intents
  Screens/                News, Table, Form, Player sheet, Injuries, Games, Search, Settings
  UI/Components.swift     club-colour band, cards, tabs, league picker
  Info.plist              URL scheme, export compliance
Shared/                   compiled into both the app and the widget
  Models, MatchdayAPI + ServerConfig (the data server), ClubBadge, FormScore, DataStore (memory + disk cache), Theme, Intents
  Fonts/                  Archivo Expanded, DM Sans (SIL Open Font License)
  PrivacyInfo.xcprivacy
MatchdayWidget/           WidgetKit extension: League table and Form leader
```

Folders are synced with Xcode, so new files inside them are picked up automatically.
