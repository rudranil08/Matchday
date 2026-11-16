# Leaderboard load test

Simulates many Matchday players signing in and playing at the same instant, against Google's
local Firebase emulators (Auth + Firestore) with the project's real `firestore.rules` (copied in from the project folder each time the emulators start, because Firebase only reads rules inside its own folder).
Nothing touches the live `matchday-14c44` project: no quota is used and no junk data is created.

## Run

Needs Node 18+ and Java 11+ (`brew install openjdk@21`).

```
cd LoadTest
npm install
JAVA_HOME=/opt/homebrew/opt/openjdk@21 npm run emulators     # terminal 1, wait for "All emulators ready"
USERS=1000 npm run load                                          # terminal 2
```

Each virtual player does what the app does: half sign up with email and password (sign up, sign in,
verification lookup), half use an anonymous identity (username, checker, Google and Apple accounts).
Then: open Games (top 5), answer 5 questions with a short pause each, post the score after every
answer, update the all-time total once, refresh the hub, and about half open the full board
(Today and All time, top 10). One in twenty also tries to post 9,999 points, which the rules must refuse.

At the end it reads the database as its owner and checks every stored score and total.
To run again on a clean database, restart the emulators (they keep data only in memory).
