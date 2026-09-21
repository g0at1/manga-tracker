import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  civilDay,
  collectUpcoming,
  copyFor,
  daysBetween,
  isPlausibleEmail,
  normalizeSettings,
  pruneSent,
  renderReminderEmail,
  renderTestEmail,
  selectDue,
  toDate,
} from "../reminders.js";

const TZ = "Europe/Warsaw";
// A Sunday morning in Warsaw (CEST, UTC+2).
const NOW = new Date("2026-09-20T06:00:00Z");
const DAY = 86_400_000;

/** A release `days` from NOW, at local midnight in Warsaw like the apps store it. */
function releaseIn(days) {
  return new Date(civilDay(NOW, TZ) + days * DAY - 2 * 3_600_000);
}

function library(...series) {
  return series.map(([id, title, volumes]) => ({
    id,
    manga: { title, coverURL: `https://img/${id}.jpg`, volumes },
  }));
}

describe("dates", () => {
  it("counts days in the library's time zone, not UTC", () => {
    // 23:30 in Warsaw on the 20th is still the 20th, though it's the 21st in UTC.
    const lateEvening = new Date("2026-09-20T21:30:00Z");
    assert.equal(daysBetween(civilDay(NOW, TZ), civilDay(lateEvening, TZ)), 0);
    assert.equal(daysBetween(civilDay(NOW, "UTC"), civilDay(lateEvening, "UTC")), 0);
    // Just past midnight Warsaw time is the next day there, still the 20th in UTC.
    const afterMidnight = new Date("2026-09-20T22:30:00Z");
    assert.equal(daysBetween(civilDay(NOW, TZ), civilDay(afterMidnight, TZ)), 1);
    assert.equal(daysBetween(civilDay(NOW, "UTC"), civilDay(afterMidnight, "UTC")), 0);
  });

  it("reads Firestore timestamps, dates, numbers and strings", () => {
    const date = new Date("2026-10-01T00:00:00Z");
    assert.equal(toDate({ toDate: () => date }), date);
    assert.equal(toDate(date), date);
    assert.equal(toDate(date.getTime()).getTime(), date.getTime());
    assert.equal(toDate("2026-10-01T00:00:00Z").getTime(), date.getTime());
    assert.equal(toDate(null), null);
    assert.equal(toDate("not a date"), null);
    assert.equal(toDate(new Date(Number.NaN)), null);
  });
});

describe("collectUpcoming", () => {
  it("keeps today and later, sorted by day, title, number", () => {
    const mangas = library(
      ["b", "Berserk", [
        { number: 2, releaseDate: releaseIn(3) },
        { number: 1, releaseDate: releaseIn(3) },
        { number: 0, releaseDate: releaseIn(-1) },
      ]],
      ["a", "akira", [{ number: 5, releaseDate: releaseIn(3), buyURL: " https://shop.example/akira-5 " }]],
      ["c", "Chainsaw Man", [{ number: 9, releaseDate: releaseIn(0) }, { number: 10 }]],
    );
    const upcoming = collectUpcoming(mangas, { now: NOW, timeZone: TZ });
    assert.deepEqual(
      upcoming.map((e) => [e.key, e.daysUntil]),
      [["c#9", 0], ["a#5", 3], ["b#1", 3], ["b#2", 3]],
    );
    assert.equal(upcoming[1].buyURL, "https://shop.example/akira-5");
    assert.equal(upcoming[1].coverURL, "https://img/a.jpg");
  });

  it("ignores volumes without a usable date and links that aren't http(s)", () => {
    const mangas = library(["x", "X", [
      { number: 1, releaseDate: "garbage" },
      { number: 2, releaseDate: releaseIn(1), buyURL: "javascript:alert(1)" },
      { number: 3, releaseDate: releaseIn(1), buyURL: "shop.example/no-scheme" },
    ]]);
    const upcoming = collectUpcoming(mangas, { now: NOW, timeZone: TZ });
    assert.deepEqual(upcoming.map((e) => [e.number, e.buyURL]), [[2, null], [3, null]]);
  });

  it("copes with documents missing the manga snapshot", () => {
    assert.deepEqual(collectUpcoming([{ id: "empty" }, { id: "novol", manga: {} }], { now: NOW, timeZone: TZ }), []);
  });
});

describe("selectDue", () => {
  const upcoming = collectUpcoming(
    library(["s", "Series", [
      { number: 1, releaseDate: releaseIn(0) },
      { number: 2, releaseDate: releaseIn(3) },
      { number: 3, releaseDate: releaseIn(4) },
    ]]),
    { now: NOW, timeZone: TZ },
  );

  it("takes what's inside the window and not announced yet", () => {
    const due = selectDue(upcoming, { daysBefore: 3, sent: {} });
    assert.deepEqual(due.map((e) => e.number), [1, 2]);
  });

  it("skips volumes already announced for the same day", () => {
    const sent = { "s#1": upcoming[0].releaseDay };
    assert.deepEqual(selectDue(upcoming, { daysBefore: 3, sent }).map((e) => e.number), [2]);
  });

  it("announces again when the release moved", () => {
    const sent = { "s#1": upcoming[0].releaseDay - DAY };
    assert.deepEqual(selectDue(upcoming, { daysBefore: 0, sent }).map((e) => e.number), [1]);
  });
});

describe("pruneSent", () => {
  it("drops old releases and junk, keeps recent and future ones", () => {
    const today = civilDay(NOW, TZ);
    const sent = {
      old: today - 61 * DAY,
      edge: today - 60 * DAY,
      recent: today - DAY,
      future: today + 10 * DAY,
      junk: "yesterday",
    };
    assert.deepEqual(pruneSent(sent, { now: NOW, timeZone: TZ }), {
      edge: today - 60 * DAY,
      recent: today - DAY,
      future: today + 10 * DAY,
    });
    assert.deepEqual(pruneSent(undefined, { now: NOW, timeZone: TZ }), {});
  });
});

describe("renderReminderEmail", () => {
  const entries = (...volumes) =>
    collectUpcoming(library(["k", "Kaiju <No. 8>", volumes]), { now: NOW, timeZone: TZ });

  it("names the single volume and the day in the subject", () => {
    const mail = renderReminderEmail(entries({ number: 12, releaseDate: releaseIn(3) }), { language: "pl", daysBefore: 3 });
    assert.equal(mail.subject, "Premiera za 3 dni: Kaiju <No. 8>, tom 12");
    const tomorrow = renderReminderEmail(entries({ number: 1, releaseDate: releaseIn(1) }), { language: "en", daysBefore: 7 });
    assert.equal(tomorrow.subject, "Release tomorrow: Kaiju <No. 8>, vol. 1");
    const today = renderReminderEmail(entries({ number: 1, releaseDate: releaseIn(0) }), { language: "pl", daysBefore: 7 });
    assert.equal(today.subject, "Premiera dziś: Kaiju <No. 8>, tom 1");
  });

  it("counts volumes with Polish plurals", () => {
    const { volumes } = copyFor("pl");
    assert.equal(volumes(1), "1 tom");
    assert.equal(volumes(2), "2 tomy");
    assert.equal(volumes(5), "5 tomów");
    assert.equal(volumes(12), "12 tomów");
    assert.equal(volumes(22), "22 tomy");
    const many = renderReminderEmail(
      entries({ number: 1, releaseDate: releaseIn(1) }, { number: 2, releaseDate: releaseIn(2) }),
      { language: "pl", daysBefore: 3 },
    );
    assert.equal(many.subject, "Nadchodzące premiery: 2 tomy");
    assert.equal(copyFor("en").volumes(2), "2 volumes");
  });

  it("links the shop, marks owned volumes and escapes HTML", () => {
    const mail = renderReminderEmail(
      entries(
        { number: 1, releaseDate: releaseIn(1), buyURL: "https://shop.example/k1?a=1&b=2" },
        { number: 2, releaseDate: releaseIn(1), owned: true, buyURL: "https://shop.example/k2" },
        { number: 3, releaseDate: releaseIn(2) },
      ),
      { language: "pl", daysBefore: 3 },
    );
    assert.match(mail.html, /href="https:\/\/shop\.example\/k1\?a=1&amp;b=2"/);
    assert.doesNotMatch(mail.html, /shop\.example\/k2/, "owned volumes get no buy button");
    assert.match(mail.html, /Masz już ten tom/);
    assert.match(mail.html, /Brak linku do zakupu/);
    assert.match(mail.html, /Kaiju &lt;No\. 8&gt;/);
    assert.doesNotMatch(mail.html, /<No\. 8>/);
    assert.match(mail.text, /Kup tom: https:\/\/shop\.example\/k1\?a=1&b=2/);
    assert.match(mail.text, /Kaiju <No\. 8> — Tom 3/);
    assert.match(mail.html, /3 dni przed premierą/);
  });

  it("groups by day with the weekday spelled out", () => {
    const mail = renderReminderEmail(
      entries({ number: 1, releaseDate: releaseIn(1) }, { number: 2, releaseDate: releaseIn(3) }),
      { language: "pl", daysBefore: 3 },
    );
    assert.match(mail.text, /poniedziałek, 21 września \(jutro\)/);
    assert.match(mail.text, /środa, 23 września \(za 3 dni\)/);
    const english = renderReminderEmail(entries({ number: 1, releaseDate: releaseIn(1) }), { language: "en", daysBefore: 1 });
    assert.match(english.text, /Monday, September 21 \(tomorrow\)/);
    assert.match(english.text, /within 1 day:/);
  });
});

describe("renderTestEmail", () => {
  const upcoming = collectUpcoming(
    library(["s", "Series", [
      { number: 1, releaseDate: releaseIn(10) },
      { number: 2, releaseDate: releaseIn(20) },
    ]]),
    { now: NOW, timeZone: TZ },
  );

  it("lists the window when something is in it", () => {
    const mail = renderTestEmail(upcoming, { language: "pl", daysBefore: 14, email: "a@b.pl" });
    assert.equal(mail.subject, "MangaTracker: test przypomnień e-mail");
    assert.match(mail.text, /Na adres a@b\.pl będą przychodzić przypomnienia 14 dni przed/);
    assert.match(mail.text, /Premiery w ciągu 14 dni:/);
    assert.match(mail.text, /Tom 1/);
    assert.doesNotMatch(mail.text, /Tom 2/);
  });

  it("falls back to the next releases when the window is empty", () => {
    const mail = renderTestEmail(upcoming, { language: "en", daysBefore: 3, email: "a@b.pl" });
    assert.match(mail.text, /Nothing is scheduled within 3 days\. Next up:/);
    assert.match(mail.text, /Vol\. 1/);
    assert.match(mail.text, /Vol\. 2/);
  });

  it("says so when nothing has a date", () => {
    const mail = renderTestEmail([], { language: "pl", daysBefore: 3, email: "a@b.pl" });
    assert.match(mail.text, /Żaden tom w bibliotece nie ma jeszcze ustawionej daty premiery\./);
  });
});

describe("settings", () => {
  it("fills defaults and clamps what the apps send", () => {
    assert.deepEqual(normalizeSettings(undefined), {
      enabled: false,
      email: "",
      daysBefore: 3,
      language: "pl",
      timeZone: "Europe/Warsaw",
    });
    assert.deepEqual(
      normalizeSettings({ enabled: true, email: " me@example.com ", daysBefore: 999, language: "en", timeZone: "Asia/Tokyo" }),
      { enabled: true, email: "me@example.com", daysBefore: 60, language: "en", timeZone: "Asia/Tokyo" },
    );
    assert.equal(normalizeSettings({ timeZone: "Mars/Olympus" }).timeZone, "Europe/Warsaw");
    assert.equal(normalizeSettings({ daysBefore: 2.5 }).daysBefore, 3);
    assert.equal(normalizeSettings({ language: "de" }).language, "pl");
  });

  it("recognises an address shape", () => {
    assert.ok(isPlausibleEmail("me@example.com"));
    assert.ok(!isPlausibleEmail(""));
    assert.ok(!isPlausibleEmail("me@example"));
    assert.ok(!isPlausibleEmail("me example@x.pl"));
  });
});
