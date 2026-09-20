# 📚 MangaTracker (macOS + iOS)

A lightweight macOS app — with an iPhone/iPad companion — built with **SwiftUI** and **SwiftData** to track your manga collection, reading progress, and personal notes. Both apps share one library through Firestore, so a volume marked read on the phone shows up on the Mac (and the other way round).

---

## ✨ Features

- 📖 Track manga titles, volumes, and reading progress  
- ✅ Mark volumes as **owned** and/or **read**  
- 📊 Automatic progress calculation (%)  
- 📝 Add personal notes to each manga  
- 📅 Track purchase and reading dates  
- 🔍 Filter:
  - All volumes
  - Missing volumes
  - Unread volumes  
- 💾 Local persistence using **SwiftData**  
- 📱 iOS companion app (library, series details, marking volumes, adding series from AniList)
- 🔄 Two-way sync between devices through Cloud Firestore (see below)
- ⚡ Fast and minimal UI built with **SwiftUI**

---

## 🚀 Getting Started

### Requirements

- macOS 26+ for the Mac app, iOS 18+ for the iPhone app
- Xcode 26+

---

### Installation

```bash
git clone https://github.com/g0at1/manga-tracker.git
cd MangaTracker
```

Open `MangaTracker.xcodeproj`. The project has three targets:

| Target | What it is |
|---|---|
| `MangaTracker` | the macOS app (`MangaTracker/` + `Shared/`) |
| `MangaTrackerIOS` | the iOS app (`MangaTrackerIOS/` + `Shared/`) |
| `MangaTrackerTests` | sync engine tests, run on the iOS simulator |

Everything platform-neutral — models, AniList client, image cache, export format, the sync engine and a few views — lives in `Shared/`.

---

## 🔄 Synchronizacja (sync)

Sync is optional: without it each app is local-only, exactly as before. Under the hood every device keeps its own SwiftData store and the sync engine (`Shared/Sync/`) mirrors it to Cloud Firestore, one document per series. Firestore's offline cache means changes made without a connection go out when one comes back. A library is identified by a random 24-character **library key**; whoever has the key can read and write that library, so treat it like a password.

### 1. Create a Firebase project (free Spark plan is enough)

1. Go to <https://console.firebase.google.com>, **Add project** (Google Analytics can stay off).
2. **Build → Firestore Database → Create database**, production mode, pick a region close to you.
3. **Rules** tab: replace the rules with the contents of [`firebase/firestore.rules`](firebase/firestore.rules) and publish. They only allow access to `libraries/{24-character key}/mangas` and forbid listing keys.
4. **Project settings → Your apps → Add app → iOS**, bundle ID `com.michalL.MangaTracker` (the same bundle ID is used by both targets, so one registration covers both). Download `GoogleService-Info.plist`.

### 2. Put the plist in the project

Copy `GoogleService-Info.plist` into `Shared/`. It's git-ignored; both targets pick it up automatically. Without it the apps run local-only and *Ustawienia → Synchronizacja* says so.

### 3. Link the devices

1. Mac: *Ustawienia → Synchronizacja → Utwórz nową bibliotekę*. The existing collection is uploaded and the key is shown — **Kopiuj**.
2. iPhone: *Ustawienia → Synchronizacja*, paste the key (Universal Clipboard works), **Połącz**. The library downloads.
3. From now on both apps stay in sync while they run; changes made while an app is closed arrive when it's opened next.

Conflicts are resolved per series: the version that reaches the server last wins on every device, except that an edit not yet sent from a device is kept until it goes out. Deleting a series on one device deletes it everywhere. **Wyślij całą bibliotekę** re-uploads everything if the two sides ever look out of step.

### Running the sync tests locally

The tests in `MangaTrackerTests` simulate two devices against the Firestore emulator (needs Node.js and Java):

```bash
cd firebase && npx firebase-tools emulators:start --only firestore --project demo-mangatracker
```

then run the `MangaTrackerIOS` scheme's tests. They skip themselves when the emulator isn't reachable. The `Tests` GitHub workflow does the same on every push: it starts the emulator on the runner, then runs the suite on an iOS simulator. Both apps can also be pointed at the emulator instead of a real project with the `MANGATRACKER_FIRESTORE_EMULATOR=127.0.0.1:8080` environment variable.
