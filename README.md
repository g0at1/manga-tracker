# 📚 MangaTracker (macOS + iOS)

A lightweight macOS app — with an iPhone/iPad companion — built with **SwiftUI** and **SwiftData** to track your manga collection, reading progress, and personal notes. Both apps share one library through Firestore, so a volume marked read on the phone shows up on the Mac (and the other way round).

---

## ✨ Features

- 📖 Track manga titles, volumes, and reading progress  
- ✅ Mark volumes as **owned** and/or **read**  
- 📚 Split a collected edition (e.g. a *Berserk Deluxe* volume holding three originals) into **parts** that are marked read one at a time; progress counts by parts  
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
- 📧 E-mail reminders a few days before a volume's release, with the purchase link (see below)
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

### Installing the Mac app

`scripts/install-mac.sh` builds the macOS app in Release and replaces `/Applications/MangaTracker.app` with it. A running copy is quit first (through the normal ⌘Q path, so pending sync goes out) and relaunched afterwards:

```bash
scripts/install-mac.sh
```

Pass a configuration name to install a different build, e.g. `scripts/install-mac.sh Debug`.

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

## 📧 Przypomnienia e-mail (release reminders)

With sync on, the apps can e-mail you a few days before a volume you track is released — one message per morning listing every volume due, with its cover and a **Kup** button when the volume has a purchase link. *Ustawienia → Przypomnienia e-mail* on either device: switch it on, enter the address, pick how many days ahead (1–14), and use **Wyślij testowy e-mail** to check the setup. The settings live on the library document, so both devices show the same values.

The e-mails come from a scheduled Cloud Function in the same Firebase project (`firebase/functions/`), not from the apps, so they arrive even when neither app is running. That has two consequences:

- **The project needs the Blaze plan.** Cloud Functions and Cloud Scheduler aren't available on Spark. Blaze wants a billing account attached, but this workload — one run a day, a handful of Firestore reads — stays well inside the free quotas; Google may bill a few cents a month for the container image storage a function deploy leaves in Artifact Registry.
- **You need an SMTP account** the function can send through. Gmail works with an [app password](https://myaccount.google.com/apppasswords) (2-step verification has to be on); iCloud, Outlook and transactional providers work the same way.

### Deploying the functions

Requires Node 22.12+ (the Cloud Functions runtime; older 22.x can't load `firebase-admin`).

1. In the Firebase console upgrade the project to **Blaze**.
2. Install the dependencies and store the SMTP password as a secret:

   ```bash
   cd firebase/functions && npm ci
   ```

   ```bash
   cd firebase && npx firebase-tools functions:secrets:set SMTP_PASSWORD --project <your-project-id>
   ```

3. Deploy the updated rules and the functions. The first deploy asks for `SMTP_HOST` (e.g. `smtp.gmail.com`), `SMTP_PORT` (465), `SMTP_USER` (the sending address) and `SMTP_FROM` (optional display name) and keeps them in `firebase/functions/.env.<project-id>`, which is git-ignored:

   ```bash
   cd firebase && npx firebase-tools deploy --only firestore:rules,functions --project <your-project-id>
   ```

   The rules changed for this feature (the library document itself is now readable and its `reminders` field writable by whoever has the key), so republishing them is required even if you only want the settings screen to load.

4. In the app, turn reminders on and send a test e-mail. The card shows when the server last checked and last sent, and why a send failed.

### How it works

`sendReleaseReminders` runs every day at 08:00 Europe/Warsaw (change `schedule`/`timeZone` in `firebase/functions/index.js`). For every library with reminders on it reads the series, picks the volumes whose release day is within the configured window and which it hasn't announced for that day yet, and sends one e-mail. What it announced is kept under `reminderLog.sent` on the library document, so a volume is announced once — unless its release date moves, which counts as news. `sendTestReminder` watches the same document and answers the **Wyślij testowy e-mail** button.

The functions have their own tests (`cd firebase/functions && npm test`): the selection and rendering logic runs anywhere; the cases that exercise the Firestore side run against the emulator when it's up and skip otherwise.

### Running the sync tests locally

The tests in `MangaTrackerTests` simulate two devices against the Firestore emulator (needs Node.js and Java):

```bash
cd firebase && npx firebase-tools emulators:start --only firestore --project demo-mangatracker
```

then run the `MangaTrackerIOS` scheme's tests. They skip themselves when the emulator isn't reachable. The `Tests` GitHub workflow does the same on every push: it starts the emulator on the runner, runs the Cloud Functions tests, then the suite on an iOS simulator. Both apps can also be pointed at the emulator instead of a real project with the `MANGATRACKER_FIRESTORE_EMULATOR=127.0.0.1:8080` environment variable.
