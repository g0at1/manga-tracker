// Runs `remindLibrary` and `sendTestForLibrary` against the Firestore
// emulator with a fake SMTP transport. Start the emulator first:
//
//     cd firebase && npx firebase-tools emulators:start --only firestore --project demo-mangatracker
//
// Skips itself when the emulator isn't reachable. Needs a Node that can
// `require()` ES modules (22.12+), like the Cloud Functions runtime.

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";

const EMULATOR = process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080";
process.env.FIRESTORE_EMULATOR_HOST = EMULATOR;
process.env.GCLOUD_PROJECT ??= "demo-mangatracker";
process.env.SMTP_USER ??= "sender@example.com";

async function emulatorReachable() {
  try {
    const response = await fetch(`http://${EMULATOR}/`);
    return response.ok;
  } catch {
    return false;
  }
}

let skip = false;
let functions;
let firestore;
if (!(await emulatorReachable())) {
  skip = `no emulator at ${EMULATOR}`;
} else {
  try {
    functions = await import("../index.js");
    firestore = await import("firebase-admin/firestore");
  } catch (error) {
    // firebase-admin needs require(esm), which Node 22 only got in 22.12.
    skip = `can't load firebase-admin on Node ${process.version}: ${error.code ?? error.message}`;
  }
}

describe("functions against the Firestore emulator", { skip }, () => {
  let db;
  let remindLibrary;
  let sendTestForLibrary;
  let libraryRef;
  const NOW = new Date("2026-09-20T06:00:00Z");
  const DAY = 86_400_000;

  /** A transport that keeps what it was asked to send. */
  function fakeTransport(fail = false) {
    const sent = [];
    return {
      sent,
      async sendMail(message) {
        if (fail) throw new Error("SMTP down");
        sent.push(message);
      },
    };
  }

  function releaseIn(days) {
    // Local midnight in Warsaw (CEST) like the apps store it.
    return new Date(Date.UTC(2026, 8, 20) + days * DAY - 2 * 3_600_000);
  }

  before(async () => {
    ({ remindLibrary, sendTestForLibrary } = functions);
    db = firestore.getFirestore();
    libraryRef = db.collection("libraries").doc(`TEST${Date.now().toString(36).toUpperCase().padStart(20, "X")}`);
    await libraryRef.set({
      reminders: {
        enabled: true,
        email: "reader@example.com",
        daysBefore: 3,
        language: "pl",
        timeZone: "Europe/Warsaw",
        updatedAt: NOW,
      },
    });
    await libraryRef.collection("mangas").doc("berserk").set({
      revision: 1,
      updatedAt: NOW,
      device: "test",
      manga: {
        title: "Berserk",
        coverURL: "https://img.example/berserk.jpg",
        volumes: [
          { number: 41, owned: true, releaseDate: releaseIn(-30) },
          { number: 42, owned: false, releaseDate: releaseIn(2), buyURL: "https://shop.example/berserk-42" },
          { number: 43, owned: false, releaseDate: releaseIn(30) },
        ],
      },
    });
  });

  after(async () => {
    if (!libraryRef) return;
    const mangas = await libraryRef.collection("mangas").get();
    await Promise.all(mangas.docs.map((doc) => doc.ref.delete()));
    await libraryRef.delete();
  });

  it("mails what's due, records it, and stays quiet the next day", async () => {
    const transport = fakeTransport();
    await remindLibrary(await libraryRef.get(), transport, NOW);

    assert.equal(transport.sent.length, 1);
    const [mail] = transport.sent;
    assert.equal(mail.to, "reader@example.com");
    assert.equal(mail.from, "MangaTracker <sender@example.com>");
    assert.equal(mail.subject, "Premiera za 2 dni: Berserk, tom 42");
    assert.match(mail.html, /https:\/\/shop\.example\/berserk-42/);
    assert.doesNotMatch(mail.text, /Tom 43/);

    const log = (await libraryRef.get()).get("reminderLog");
    assert.equal(log.lastRunAt.toMillis(), NOW.getTime());
    assert.equal(log.lastSentAt.toMillis(), NOW.getTime());
    assert.equal(log.lastError, undefined);
    assert.deepEqual(Object.keys(log.sent), ["berserk#42"]);

    // Tomorrow: volume 42 is still inside the window but already announced.
    const tomorrow = fakeTransport();
    await remindLibrary(await libraryRef.get(), tomorrow, new Date(NOW.getTime() + DAY));
    assert.equal(tomorrow.sent.length, 0);
    const later = (await libraryRef.get()).get("reminderLog");
    assert.equal(later.lastRunAt.toMillis(), NOW.getTime() + DAY);
    assert.equal(later.lastSentAt.toMillis(), NOW.getTime(), "lastSentAt only moves when something goes out");
  });

  it("keeps the volume unannounced when sending fails, and reports why", async () => {
    // Volume 43 enters the window 27 days from NOW.
    const day = new Date(NOW.getTime() + 27 * DAY);
    await remindLibrary(await libraryRef.get(), fakeTransport(true), day);
    let log = (await libraryRef.get()).get("reminderLog");
    assert.equal(log.lastError, "SMTP down");
    assert.deepEqual(Object.keys(log.sent).sort(), ["berserk#42"]);

    const transport = fakeTransport();
    await remindLibrary(await libraryRef.get(), transport, day);
    assert.equal(transport.sent.length, 1);
    assert.match(transport.sent[0].subject, /Berserk, tom 43/);
    log = (await libraryRef.get()).get("reminderLog");
    assert.equal(log.lastError, undefined);
    assert.deepEqual(Object.keys(log.sent).sort(), ["berserk#42", "berserk#43"]);
  });

  it("refuses a library without a usable address", async () => {
    await libraryRef.update({ "reminders.email": "nope" });
    const transport = fakeTransport();
    await remindLibrary(await libraryRef.get(), transport, NOW);
    assert.equal(transport.sent.length, 0);
    assert.equal((await libraryRef.get()).get("reminderLog.lastError"), "Brak poprawnego adresu e-mail.");
    await libraryRef.update({ "reminders.email": "reader@example.com" });
  });

  it("answers a test request with the same timestamp", async () => {
    const requestedAt = new Date("2026-09-20T06:05:00Z");
    const transport = fakeTransport();
    await sendTestForLibrary(await libraryRef.get(), requestedAt, transport, NOW);
    assert.equal(transport.sent.length, 1);
    assert.equal(transport.sent[0].subject, "MangaTracker: test przypomnień e-mail");
    assert.match(transport.sent[0].text, /Premiery w ciągu 3 dni:/);
    assert.match(transport.sent[0].text, /Tom 42/);

    const test = (await libraryRef.get()).get("reminderLog.test");
    assert.equal(test.requestedAt.toMillis(), requestedAt.getTime());
    assert.equal(test.sentAt.toMillis(), NOW.getTime());
    assert.equal(test.error, undefined);

    const failing = fakeTransport(true);
    await sendTestForLibrary(await libraryRef.get(), requestedAt, failing, NOW);
    const failed = (await libraryRef.get()).get("reminderLog.test");
    assert.equal(failed.error, "SMTP down");
    assert.equal(failed.sentAt, undefined);
  });
});
