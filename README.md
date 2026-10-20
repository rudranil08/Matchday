# Matchday

A native iOS app for football fans following the **Premier League, LaLiga, Bundesliga and Ligue 1**: live tables, news, injuries, a player Form score, and a daily quiz with a leaderboard. Built in SwiftUI, with no third-party SDKs.

| News | Table | Form | Injuries |
|---|---|---|---|
| ![News](docs/screenshots/news.png) | ![Table](docs/screenshots/table.png) | ![Form](docs/screenshots/form.png) | ![Injuries](docs/screenshots/injuries.png) |

## Features

**Football**
- **News** for your leagues, in sections: your club, match reports, transfers, injuries
- **Tables** for all four leagues, with your clubs highlighted and European and relegation places marked
- **Form score (0–100)** for every player, from goals, assists, minutes played and fitness, with a plain-language "why"
- **Injuries**: who's out, who's doubtful, and when they're expected back
- **Your clubs**: pick two or more leagues and one club per league; the app takes on your club's colours

**Games**
- **Daily quiz**: five questions a day, different for every player, mixing classic trivia with questions built from today's live data. 100 points per right answer, plus up to 50 for speed
- **Leaderboard**: today and all time, with server-side rules that reject impossible scores
- **Who's in better form?**: a quick head-to-head between two in-form players

**iPhone features**
- Home Screen and Lock Screen widgets (league table, form leader)
- Siri and Shortcuts ("Who's top of the league in Matchday?")
- iOS 26+: **Catch me up**, a three-point summary of your club's news written on the device by Apple Intelligence
- iOS 26+: your club's position in a strip above the tab bar (on iOS 27 the tab bar also shrinks as you scroll)
- iOS 27: swipe to follow a club; drag to reorder your leagues
- Works offline from saved data, opens instantly, and refreshes in the background
- Dynamic Type, VoiceOver labels, light and dark mode

**Accounts and privacy**
- Email and password (Firebase), username accounts stored only on the iPhone, Sign in with Apple, and Google sign-in
- Remember me, forgot password, change password, and full account deletion (including leaderboard data)
- A neutral age check before sign-up. Under-13s use guest mode, where nothing leaves the iPhone
- Privacy Policy, Terms of Use and Copyright pages in the app. Players can report or hide leaderboard names
- No ads, no analytics, no tracking

## Tech

| | |
|---|---|
| UI | SwiftUI, iOS 17+ (newer features behind `#available`) |
| State | `@Observable`, Swift concurrency (actors, task groups) |
| Data | ESPN and FotMob public feeds; disk and memory cache with offline fallback |
| Accounts | Firebase Authentication REST API, Keychain, PBKDF2 for local passwords |
| Leaderboard | Cloud Firestore REST API with security rules |
| On-device AI | FoundationModels (weak-linked) |
| Extensions | WidgetKit, App Intents |
| Tests | XCUITest: feature, reliability, chaos (fault injection) and compliance suites |

No CocoaPods or Swift packages: Firebase and Google sign-in are called over plain HTTPS.

## Getting started

**Requirements:** Xcode 27 or later, and an iOS 17+ simulator or device.

1. Clone the repo and open `Matchday.xcodeproj`.
2. Create `Shared/Secrets.swift`. It's git-ignored, so each person keeps their own:

   ```swift
   enum Secrets {
       /// Optional: paid API-Football key for injuries (FotMob is used by default).
       static let apiFootballKey = ""
       /// Optional: Google sign-in (iOS OAuth client ID).
       static let googleClientID = ""
       /// Firebase project for email accounts and the leaderboard.
       static let firebaseProjectID = ""
       static let firebaseAPIKey = ""
   }
   ```

3. Choose an iPhone simulator and press **⌘R**.

The app runs with every value empty. Email accounts, Google sign-in and the leaderboard each turn on once their value is set.

### Firebase setup (email accounts and leaderboard)

1. Create a project at [console.firebase.google.com](https://console.firebase.google.com).
2. **Authentication › Sign-in method:** turn on **Email/Password** and **Anonymous**.
3. **Project settings › General:** copy the project ID and Web API key into `Secrets.swift`.
4. **Firestore Database:** create a database, then paste [`firestore.rules`](firestore.rules) into **Rules** and click **Publish**.

The free Spark plan covers about 2,000 quiz players a day.

### Before you release
- **Legal details:** fill in `Matchday/Legal/LegalInfo.swift` (operator name, contact email), then run `python3 legal/build.py` to build the web versions of the legal pages and host them.
- **Developer account:** change the built-in developer account's credentials in `Matchday/Auth/AuthStore.swift`.
- **Data licence:** ESPN and FotMob are unofficial public feeds. Use a licensed data provider for a public release.
- **Sign in with Apple** needs a paid Apple Developer team.

## Tests

Press **⌘U** on an iPhone simulator. Run on both iOS 26 and iOS 27 if you can. DEBUG-only launch flags sign in a test account with two clubs, so no real account is needed.

| Suite | What it covers |
|---|---|
| `NewFeatureTests` | Swipe to follow, reorder leagues, Catch me up, daily quiz, form duel, leaderboard end to end |
| `ReliabilityTests` | Offline mode, cold-launch time, a tour of every tab and league |
| `ChaosTests` | Every screen while requests time out, drop, error or return garbage |
| `ComplianceTests` | Age gate, guest mode, legal pages, hiding names |

`LoadTest/` simulates 1,000 players signing in and playing at the same moment, against the local Firebase emulator using the real security rules. See `LoadTest/README.md`.

## Project layout

```
Matchday/            App: screens, onboarding, auth, games, legal, iOS 26/27 features
Shared/              Shared with the widget: models, data feeds, cache, theme, fonts
MatchdayWidget/      Home Screen and Lock Screen widgets
MatchdayUITests/     UI test suites
LoadTest/            1,000-player Firebase load test (emulator)
legal/               Web versions of the legal pages
firestore.rules      Leaderboard security rules
```

## Disclaimer

Matchday isn't affiliated with any league, club, ESPN or FotMob. Club names, crests and news belong to their owners.

## License

Add a license here (for example MIT) before making the repository public.
