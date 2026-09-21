// MangaTracker Cloud Functions: e-mail reminders before volume releases.
//
// `sendReleaseReminders` runs every morning, reads every library with
// reminders switched on, and mails the volumes releasing within the
// library's "days before" window that it hasn't announced yet.
// `sendTestReminder` answers the "Wyślij testowy e-mail" button in the
// apps, which works by stamping `reminders.testRequestedAt` on the
// library document.
//
// Both write only under `reminderLog` on the library document; the apps
// write only `reminders`, so neither side overwrites the other.

import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { defineInt, defineSecret, defineString } from "firebase-functions/params";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import nodemailer from "nodemailer";

import {
  collectUpcoming,
  isPlausibleEmail,
  normalizeSettings,
  pruneSent,
  renderReminderEmail,
  renderTestEmail,
  selectDue,
  toDate,
} from "./reminders.js";

// With FIRESTORE_EMULATOR_HOST set this talks to the emulator instead,
// which is how test/ exercises the exported functions below.
initializeApp();
const db = getFirestore();

// Asked for on the first `firebase deploy` and kept in functions/.env.<project>
// (git-ignored); the password is a Secret Manager secret. Any SMTP account
// works — Gmail with an app password, iCloud, a transactional provider.
const smtpHost = defineString("SMTP_HOST", { description: "SMTP server, e.g. smtp.gmail.com" });
const smtpPort = defineInt("SMTP_PORT", { default: 465, description: "465 for TLS, 587 for STARTTLS" });
const smtpUser = defineString("SMTP_USER", { description: "SMTP login, usually the sending address" });
const smtpPassword = defineSecret("SMTP_PASSWORD");
const smtpFrom = defineString("SMTP_FROM", {
  default: "",
  description: 'From header, e.g. "MangaTracker <me@gmail.com>"; empty uses SMTP_USER',
});

/// Close to a Polish user; Cloud Scheduler is available here for v2 functions.
const REGION = "europe-west1";

function makeTransport() {
  const port = smtpPort.value();
  return nodemailer.createTransport({
    host: smtpHost.value(),
    port,
    secure: port === 465,
    auth: { user: smtpUser.value(), pass: smtpPassword.value() },
  });
}

function fromAddress() {
  return smtpFrom.value() || `MangaTracker <${smtpUser.value()}>`;
}

/** Every series document of a library, as `collectUpcoming` expects it. */
async function loadMangas(libraryRef) {
  const snapshot = await libraryRef.collection("mangas").get();
  return snapshot.docs.map((doc) => ({ id: doc.id, manga: doc.get("manga") }));
}

// MARK: - Daily reminders

export const sendReleaseReminders = onSchedule(
  {
    schedule: "every day 08:00",
    timeZone: "Europe/Warsaw",
    region: REGION,
    secrets: [smtpPassword],
    memory: "256MiB",
    timeoutSeconds: 300,
  },
  async () => {
    const libraries = await db.collection("libraries").where("reminders.enabled", "==", true).get();
    logger.info(`Checking ${libraries.size} librar${libraries.size === 1 ? "y" : "ies"} for upcoming releases`);
    const transport = makeTransport();
    for (const library of libraries.docs) {
      try {
        await remindLibrary(library, transport);
      } catch (error) {
        // One broken library shouldn't stop the others.
        logger.error(`Library ${library.id}: ${error?.message ?? error}`);
      }
    }
  },
);

/**
 * One library's daily check: mails what's due and records it under
 * `reminderLog`. Exported for the emulator tests, which pass a fake
 * transport and a fixed `now`.
 *
 * @param {import("firebase-admin/firestore").DocumentSnapshot} library
 * @param {{sendMail: (message: object) => Promise<unknown>}} transport
 */
export async function remindLibrary(library, transport, now = new Date()) {
  const settings = normalizeSettings(library.get("reminders"));
  const log = library.get("reminderLog") ?? {};
  const updates = { "reminderLog.lastRunAt": now };

  if (!isPlausibleEmail(settings.email)) {
    updates["reminderLog.lastError"] = "Brak poprawnego adresu e-mail.";
    await library.ref.update(updates);
    return;
  }

  const mangas = await loadMangas(library.ref);
  const upcoming = collectUpcoming(mangas, { now, timeZone: settings.timeZone });
  const sent = pruneSent(log.sent, { now, timeZone: settings.timeZone });
  const due = selectDue(upcoming, { daysBefore: settings.daysBefore, sent });
  updates["reminderLog.sent"] = sent;

  if (due.length > 0) {
    const mail = renderReminderEmail(due, settings);
    try {
      await transport.sendMail({ from: fromAddress(), to: settings.email, ...mail });
      for (const entry of due) {
        sent[entry.key] = entry.releaseDay;
      }
      updates["reminderLog.lastSentAt"] = now;
      // A stale error from an earlier failure would mislead the settings screen.
      updates["reminderLog.lastError"] = FieldValue.delete();
      logger.info(`Library ${library.id}: sent ${due.length} release(s) to ${settings.email}`);
    } catch (error) {
      // Left out of `sent`, so tomorrow's run tries again.
      updates["reminderLog.lastError"] = `${error?.message ?? error}`;
      logger.error(`Library ${library.id}: sending failed: ${error?.message ?? error}`);
    }
  }

  await library.ref.update(updates);
}

// MARK: - Test e-mail

export const sendTestReminder = onDocumentWritten(
  {
    document: "libraries/{libraryKey}",
    region: REGION,
    secrets: [smtpPassword],
    memory: "256MiB",
  },
  async (event) => {
    const after = event.data?.after;
    if (!after?.exists) return;
    const requestedAt = toDate(after.get("reminders.testRequestedAt"));
    if (!requestedAt) return;
    const before = event.data.before;
    const previous = before.exists ? toDate(before.get("reminders.testRequestedAt")) : null;
    // Every other write to the document — settings edits, our own log
    // updates — leaves the stamp alone and ends here.
    if (previous && previous.getTime() === requestedAt.getTime()) return;

    await sendTestForLibrary(after, requestedAt, makeTransport());
  },
);

/**
 * Sends the test e-mail for `library` and records the outcome under
 * `reminderLog.test`, tagged with `requestedAt` so the apps can match it
 * to their request. Exported for the emulator tests.
 *
 * @param {import("firebase-admin/firestore").DocumentSnapshot} library
 * @param {Date} requestedAt
 * @param {{sendMail: (message: object) => Promise<unknown>}} transport
 */
export async function sendTestForLibrary(library, requestedAt, transport, now = new Date()) {
  const settings = normalizeSettings(library.get("reminders"));
  const result = { requestedAt };
  if (!isPlausibleEmail(settings.email)) {
    result.error = "Brak poprawnego adresu e-mail.";
  } else {
    try {
      const mangas = await loadMangas(library.ref);
      const upcoming = collectUpcoming(mangas, { now, timeZone: settings.timeZone });
      const mail = renderTestEmail(upcoming, settings);
      await transport.sendMail({ from: fromAddress(), to: settings.email, ...mail });
      result.sentAt = now;
      logger.info(`Library ${library.id}: test e-mail sent to ${settings.email}`);
    } catch (error) {
      result.error = `${error?.message ?? error}`;
      logger.error(`Library ${library.id}: test e-mail failed: ${error?.message ?? error}`);
    }
  }
  await library.ref.update({ "reminderLog.test": result });
}
