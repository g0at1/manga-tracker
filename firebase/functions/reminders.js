// The part of the reminders that doesn't touch Firestore or SMTP: which
// volumes are due for a reminder, and the e-mail announcing them. Kept
// pure so `node --test` can cover it without a Firebase project.

const DAY_MS = 86_400_000;

/**
 * Accepts every shape a release date reaches us in: a Firestore
 * `Timestamp` (has `toDate`), a `Date`, epoch milliseconds or an ISO string.
 * @returns {Date | null}
 */
export function toDate(value) {
  if (value == null) return null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  if (typeof value.toDate === "function") return toDate(value.toDate());
  if (typeof value === "number" || typeof value === "string") {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

/**
 * The calendar day `date` falls on in `timeZone`, as the UTC midnight of
 * that day — so two days subtract to a whole number of `DAY_MS`.
 */
export function civilDay(date, timeZone) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const part = (type) => Number(parts.find((p) => p.type === type).value);
  return Date.UTC(part("year"), part("month") - 1, part("day"));
}

/** Whole days from `fromDay` to `toDay`, both from `civilDay`. */
export function daysBetween(fromDay, toDay) {
  return Math.round((toDay - fromDay) / DAY_MS);
}

/** `true` for an `http(s)` link worth putting in an e-mail. */
function buyLink(raw) {
  const trimmed = typeof raw === "string" ? raw.trim() : "";
  if (!trimmed) return null;
  try {
    const url = new URL(trimmed);
    return url.protocol === "http:" || url.protocol === "https:" ? url.href : null;
  } catch {
    return null;
  }
}

/**
 * Every volume whose release day is today or later, soonest first.
 *
 * @param {Array<{id: string, manga?: object}>} mangas documents of
 *   `libraries/{key}/mangas`: the document id plus its `manga` snapshot
 * @param {{now: Date, timeZone: string}} options
 */
export function collectUpcoming(mangas, { now, timeZone }) {
  const today = civilDay(now, timeZone);
  const entries = [];
  for (const doc of mangas) {
    const manga = doc.manga;
    if (!manga || !Array.isArray(manga.volumes)) continue;
    for (const volume of manga.volumes) {
      const releaseDate = toDate(volume?.releaseDate);
      if (!releaseDate || typeof volume.number !== "number") continue;
      const releaseDay = civilDay(releaseDate, timeZone);
      const daysUntil = daysBetween(today, releaseDay);
      if (daysUntil < 0) continue;
      entries.push({
        // Stable across runs: the series' sync id and the volume number.
        key: `${doc.id}#${volume.number}`,
        title: manga.title ?? "",
        coverURL: typeof manga.coverURL === "string" ? manga.coverURL : null,
        number: volume.number,
        releaseDay,
        daysUntil,
        buyURL: buyLink(volume.buyURL),
        owned: volume.owned === true,
      });
    }
  }
  entries.sort(
    (a, b) =>
      a.releaseDay - b.releaseDay ||
      a.title.localeCompare(b.title, undefined, { sensitivity: "base" }) ||
      a.number - b.number,
  );
  return entries;
}

/**
 * The upcoming entries to announce now: within `daysBefore` days and not
 * already announced for this release day. A volume whose date moved is
 * announced again — a postponed release is news too.
 *
 * @param {ReturnType<typeof collectUpcoming>} upcoming
 * @param {{daysBefore: number, sent: Record<string, number>}} options
 *   `sent` maps an entry key to the release day it was announced for
 */
export function selectDue(upcoming, { daysBefore, sent }) {
  return upcoming.filter((entry) => entry.daysUntil <= daysBefore && sent[entry.key] !== entry.releaseDay);
}

/**
 * Drops announcements for releases more than `keepDays` in the past, so
 * the map on the library document doesn't grow forever.
 */
export function pruneSent(sent, { now, timeZone, keepDays = 60 }) {
  const cutoff = civilDay(now, timeZone) - keepDays * DAY_MS;
  const kept = {};
  for (const [key, releaseDay] of Object.entries(sent ?? {})) {
    if (typeof releaseDay === "number" && releaseDay >= cutoff) {
      kept[key] = releaseDay;
    }
  }
  return kept;
}

// MARK: - E-mail

const COPY = {
  pl: {
    locale: "pl-PL",
    today: "dziś",
    tomorrow: "jutro",
    inDays: (n) => `za ${n} dni`,
    volume: (n) => `Tom ${n}`,
    volumes: (n) => {
      const tens = n % 10;
      const hundreds = n % 100;
      if (n === 1) return "1 tom";
      if (tens >= 2 && tens <= 4 && !(hundreds >= 12 && hundreds <= 14)) return `${n} tomy`;
      return `${n} tomów`;
    },
    subjectOne: (entry, when) => `Premiera ${when}: ${entry.title}, tom ${entry.number}`,
    subjectMany: (count) => `Nadchodzące premiery: ${count}`,
    heading: "Nadchodzące premiery",
    intro: (daysBefore) =>
      `Te tomy z Twojej biblioteki wychodzą w ciągu ${daysBefore === 1 ? "1 dnia" : `${daysBefore} dni`}:`,
    buy: "Kup tom",
    owned: "✓ Masz już ten tom",
    noLink: "Brak linku do zakupu — dodaj go w aplikacji",
    footer: (daysBefore) =>
      `Ten e-mail wysłała aplikacja MangaTracker: w Ustawieniach → Przypomnienia e-mail włączone są przypomnienia ${daysBefore === 1 ? "1 dzień" : `${daysBefore} dni`} przed premierą. Żeby przestać je dostawać, wyłącz je tam.`,
    testSubject: "MangaTracker: test przypomnień e-mail",
    testHeading: "Przypomnienia działają",
    testIntro: (email, daysBefore) =>
      `Na adres ${email} będą przychodzić przypomnienia ${daysBefore === 1 ? "1 dzień" : `${daysBefore} dni`} przed premierą tomów z Twojej biblioteki, raz dziennie rano.`,
    testWindow: (daysBefore) => `Premiery w ciągu ${daysBefore === 1 ? "1 dnia" : `${daysBefore} dni`}:`,
    testEmpty: (daysBefore) =>
      `W ciągu ${daysBefore === 1 ? "1 dnia" : `${daysBefore} dni`} nie ma zaplanowanych premier. Najbliższe:`,
    testNothing: "Żaden tom w bibliotece nie ma jeszcze ustawionej daty premiery.",
  },
  en: {
    locale: "en-US",
    today: "today",
    tomorrow: "tomorrow",
    inDays: (n) => `in ${n} days`,
    volume: (n) => `Vol. ${n}`,
    volumes: (n) => (n === 1 ? "1 volume" : `${n} volumes`),
    subjectOne: (entry, when) => `Release ${when}: ${entry.title}, vol. ${entry.number}`,
    subjectMany: (count) => `Upcoming releases: ${count}`,
    heading: "Upcoming releases",
    intro: (daysBefore) =>
      `These volumes from your library come out within ${daysBefore === 1 ? "1 day" : `${daysBefore} days`}:`,
    buy: "Buy",
    owned: "✓ Already in your collection",
    noLink: "No purchase link — add one in the app",
    footer: (daysBefore) =>
      `Sent by MangaTracker because Settings → E-mail reminders is set to remind you ${daysBefore === 1 ? "1 day" : `${daysBefore} days`} before a release. Turn it off there to stop these e-mails.`,
    testSubject: "MangaTracker: e-mail reminders test",
    testHeading: "Reminders are working",
    testIntro: (email, daysBefore) =>
      `${email} will get a reminder ${daysBefore === 1 ? "1 day" : `${daysBefore} days`} before volumes from your library are released, once a day in the morning.`,
    testWindow: (daysBefore) => `Releases within ${daysBefore === 1 ? "1 day" : `${daysBefore} days`}:`,
    testEmpty: (daysBefore) => `Nothing is scheduled within ${daysBefore === 1 ? "1 day" : `${daysBefore} days`}. Next up:`,
    testNothing: "No volume in the library has a release date yet.",
  },
};

export function copyFor(language) {
  return COPY[language] ?? COPY.pl;
}

function relative(entry, copy) {
  if (entry.daysUntil === 0) return copy.today;
  if (entry.daysUntil === 1) return copy.tomorrow;
  return copy.inDays(entry.daysUntil);
}

function longDate(releaseDay, copy) {
  // `releaseDay` is a UTC midnight, so format it in UTC to get that day back.
  return new Intl.DateTimeFormat(copy.locale, {
    timeZone: "UTC",
    weekday: "long",
    day: "numeric",
    month: "long",
  }).format(new Date(releaseDay));
}

function escapeHTML(text) {
  return String(text)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

/** Entries grouped by release day, in order. */
function byDay(entries) {
  const groups = [];
  for (const entry of entries) {
    const last = groups.at(-1);
    if (last && last.releaseDay === entry.releaseDay) {
      last.entries.push(entry);
    } else {
      groups.push({ releaseDay: entry.releaseDay, entries: [entry] });
    }
  }
  return groups;
}

function entryAction(entry, copy) {
  if (entry.owned) return { text: copy.owned, html: `<span style="color:#3c8a4e;font-size:13px;">${escapeHTML(copy.owned)}</span>` };
  if (entry.buyURL) {
    return {
      text: `${copy.buy}: ${entry.buyURL}`,
      html: `<a href="${escapeHTML(entry.buyURL)}" style="display:inline-block;padding:7px 14px;border-radius:8px;background:#2f9e44;color:#ffffff;font-size:13px;font-weight:600;text-decoration:none;">${escapeHTML(copy.buy)}</a>`,
    };
  }
  return { text: copy.noLink, html: `<span style="color:#8a8a8a;font-size:12px;">${escapeHTML(copy.noLink)}</span>` };
}

/**
 * The list section shared by the reminder and the test e-mail: one block
 * per release day, one row per volume with cover, title and buy button.
 */
function renderList(entries, copy) {
  const text = [];
  const html = [];
  for (const group of byDay(entries)) {
    const when = relative(group.entries[0], copy);
    const day = longDate(group.releaseDay, copy);
    text.push(`${day} (${when})`);
    html.push(
      `<p style="margin:22px 0 8px;font-size:13px;font-weight:600;color:#666;text-transform:uppercase;letter-spacing:0.04em;">${escapeHTML(day)} · ${escapeHTML(when)}</p>`,
    );
    for (const entry of group.entries) {
      const action = entryAction(entry, copy);
      text.push(`  • ${entry.title} — ${copy.volume(entry.number)}`);
      text.push(`    ${action.text}`);
      const cover = entry.coverURL
        ? `<img src="${escapeHTML(entry.coverURL)}" width="48" height="68" alt="" style="display:block;width:48px;height:68px;object-fit:cover;border-radius:6px;background:#e5e5e5;">`
        : `<div style="width:48px;height:68px;border-radius:6px;background:#e5e5e5;"></div>`;
      html.push(
        `<table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;margin:0 0 10px;"><tr>` +
          `<td style="width:48px;vertical-align:top;padding:0 14px 0 0;">${cover}</td>` +
          `<td style="vertical-align:top;">` +
          `<p style="margin:0 0 2px;font-size:16px;font-weight:600;color:#111;">${escapeHTML(entry.title)}</p>` +
          `<p style="margin:0 0 8px;font-size:13px;color:#666;">${escapeHTML(copy.volume(entry.number))}</p>` +
          action.html +
          `</td></tr></table>`,
      );
    }
    text.push("");
  }
  return { text: text.join("\n"), html: html.join("\n") };
}

function wrapHTML(title, body) {
  return (
    `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${escapeHTML(title)}</title></head>` +
    `<body style="margin:0;padding:24px 12px;background:#f4f4f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">` +
    `<div style="max-width:560px;margin:0 auto;background:#ffffff;border-radius:14px;padding:26px 26px 20px;">` +
    body +
    `</div></body></html>`
  );
}

function footerHTML(copy, daysBefore) {
  return `<p style="margin:26px 0 0;padding-top:14px;border-top:1px solid #eee;font-size:12px;line-height:1.5;color:#8a8a8a;">${escapeHTML(copy.footer(daysBefore))}</p>`;
}

/**
 * The daily reminder for `entries` (from `selectDue`, non-empty).
 * @returns {{subject: string, text: string, html: string}}
 */
export function renderReminderEmail(entries, { language, daysBefore }) {
  const copy = copyFor(language);
  const subject =
    entries.length === 1 ? copy.subjectOne(entries[0], relative(entries[0], copy)) : copy.subjectMany(copy.volumes(entries.length));
  const list = renderList(entries, copy);
  const text = [copy.heading, "", copy.intro(daysBefore), "", list.text, copy.footer(daysBefore)].join("\n");
  const html = wrapHTML(
    subject,
    `<h1 style="margin:0 0 6px;font-size:22px;color:#111;">${escapeHTML(copy.heading)}</h1>` +
      `<p style="margin:0;font-size:14px;color:#444;">${escapeHTML(copy.intro(daysBefore))}</p>` +
      list.html +
      footerHTML(copy, daysBefore),
  );
  return { subject, text, html };
}

/**
 * What "Wyślij testowy e-mail" delivers: confirmation of the address and
 * window, plus whatever a real reminder would list right now — or, when
 * the window is empty, the next few releases so the list isn't blank.
 */
export function renderTestEmail(upcoming, { language, daysBefore, email, previewCount = 5 }) {
  const copy = copyFor(language);
  const inWindow = upcoming.filter((entry) => entry.daysUntil <= daysBefore);
  let caption;
  let entries;
  if (inWindow.length > 0) {
    caption = copy.testWindow(daysBefore);
    entries = inWindow;
  } else if (upcoming.length > 0) {
    caption = copy.testEmpty(daysBefore);
    entries = upcoming.slice(0, previewCount);
  } else {
    caption = copy.testNothing;
    entries = [];
  }
  const list = renderList(entries, copy);
  const text = [copy.testHeading, "", copy.testIntro(email, daysBefore), "", caption, "", list.text, copy.footer(daysBefore)].join(
    "\n",
  );
  const html = wrapHTML(
    copy.testSubject,
    `<h1 style="margin:0 0 6px;font-size:22px;color:#111;">${escapeHTML(copy.testHeading)}</h1>` +
      `<p style="margin:0 0 16px;font-size:14px;color:#444;">${escapeHTML(copy.testIntro(email, daysBefore))}</p>` +
      `<p style="margin:0;font-size:14px;color:#444;">${escapeHTML(caption)}</p>` +
      list.html +
      footerHTML(copy, daysBefore),
  );
  return { subject: copy.testSubject, text, html };
}

/**
 * The `reminders` map as the apps write it, with defaults for anything
 * missing so the rest of the code can trust the shape.
 */
export function normalizeSettings(raw) {
  const settings = raw && typeof raw === "object" ? raw : {};
  const daysBefore = Number.isInteger(settings.daysBefore) ? settings.daysBefore : 3;
  return {
    enabled: settings.enabled === true,
    email: typeof settings.email === "string" ? settings.email.trim() : "",
    daysBefore: Math.min(Math.max(daysBefore, 0), 60),
    language: settings.language === "en" ? "en" : "pl",
    timeZone: validTimeZone(settings.timeZone) ? settings.timeZone : "Europe/Warsaw",
  };
}

function validTimeZone(name) {
  if (typeof name !== "string" || !name) return false;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: name });
    return true;
  } catch {
    return false;
  }
}

/** Good enough to catch a typo before an SMTP server rejects it. */
export function isPlausibleEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}
