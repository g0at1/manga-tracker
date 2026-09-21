import Foundation
import Observation

/// E-mail reminder preferences for a library. Stored on the library's
/// backend document (under `reminders`), so both devices show the same
/// values and the Cloud Function that sends the e-mails reads them there.
struct ReminderSettings: Codable, Equatable {
    var enabled: Bool
    var email: String
    /// The e-mail goes out this many days before a volume's release date
    /// (0 = on the day).
    var daysBefore: Int
    /// `AppLanguage` raw value the e-mail is written in.
    var language: String
    /// IANA zone the server counts "days before" in.
    var timeZone: String
    var updatedAt: Date
    /// Stamped by "Wyślij testowy e-mail"; the server answers in
    /// `ReminderLog.test` with the same `requestedAt`.
    var testRequestedAt: Date?

    static let daysBeforeOptions = [1, 2, 3, 5, 7, 14]

    /// What a library starts with before anyone touches the settings.
    static func initial() -> ReminderSettings {
        ReminderSettings(
            enabled: false,
            email: "",
            daysBefore: 3,
            language: AppLanguage.current.rawValue,
            timeZone: TimeZone.current.identifier,
            updatedAt: .now
        )
    }

    /// Good enough to catch a typo before the server does; the server
    /// applies the same shape check.
    static func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil
    }
}

/// What the Cloud Functions write back on the library document under
/// `reminderLog`. Read-only for the apps.
struct ReminderLog: Codable, Equatable {
    struct TestResult: Codable, Equatable {
        var requestedAt: Date?
        var sentAt: Date?
        var error: String?
    }

    /// The daily run last looked at this library.
    var lastRunAt: Date?
    /// A reminder was last e-mailed.
    var lastSentAt: Date?
    /// Why the last attempt to send failed; cleared by the next success.
    var lastError: String?
    var test: TestResult?
}

/// The library document: everything on it that isn't the `mangas`
/// subcollection. Unknown fields (the server's `sent` bookkeeping) are
/// ignored on decode.
struct RemoteLibrary: Codable {
    var reminders: ReminderSettings?
    var reminderLog: ReminderLog?
}

/// The reminder settings of the connected library, mirrored from the
/// backend and written back on every change. Owned and driven by
/// `SyncEngine`: attached when a library connects, detached when it
/// disconnects.
@MainActor
@Observable
final class LibraryReminders {
    /// `nil` until the first snapshot arrives; a library nobody has
    /// configured yet then shows `ReminderSettings.initial()`.
    private(set) var settings: ReminderSettings?
    private(set) var log: ReminderLog?
    /// The backend rejected the last write (rules, offline for good…).
    private(set) var error: String?

    var isLoaded: Bool {
        settings != nil
    }

    /// A test was asked for and the server hasn't answered yet.
    var isTestPending: Bool {
        settings?.testRequestedAt != nil && latestTestResult == nil
    }

    /// The server's answer to the latest test request, once it's in.
    var latestTestResult: ReminderLog.TestResult? {
        guard let requestedAt = settings?.testRequestedAt, let test = log?.test, let answered = test.requestedAt,
              // The stamp makes a round trip through the backend, which
              // keeps microseconds; compare loosely rather than bit-exact.
              abs(answered.timeIntervalSince(requestedAt)) < 0.001
        else { return nil }
        return test
    }

    private let backend: (any SyncBackend)?
    private var libraryKey: String?

    init(backend: (any SyncBackend)?) {
        self.backend = backend
    }

    func attach(libraryKey key: String) {
        guard let backend else { return }
        detach()
        libraryKey = key
        backend.listenLibrary(libraryKey: key) { [weak self] result in
            guard let self, libraryKey == key else { return }
            switch result {
            case let .success(library):
                settings = library?.reminders ?? .initial()
                log = library?.reminderLog
                error = nil
            case let .failure(failure):
                error = failure.localizedDescription
            }
        }
    }

    func detach() {
        backend?.stopListeningLibrary()
        libraryKey = nil
        settings = nil
        log = nil
        error = nil
    }

    /// Saves `settings` for the connected library. Shown immediately; the
    /// snapshot that follows confirms it (or `error` says why not).
    func save(_ updated: ReminderSettings) {
        guard let backend, let key = libraryKey else { return }
        var settings = updated
        settings.email = settings.email.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.language = AppLanguage.current.rawValue
        settings.timeZone = TimeZone.current.identifier
        settings.updatedAt = .now
        self.settings = settings
        backend.writeReminderSettings(libraryKey: key, settings) { [weak self] error in
            guard let self, libraryKey == key else { return }
            self.error = error?.localizedDescription
        }
    }

    /// Asks the server to send a test e-mail to the configured address now.
    func requestTest() {
        guard var settings else { return }
        settings.testRequestedAt = .now
        save(settings)
    }
}
