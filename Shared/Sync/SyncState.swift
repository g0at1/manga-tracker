import Foundation

/// The key that names a library in the backend. Whoever knows it can read
/// and write that library, so it doubles as the "account": generate it on
/// one device, type it into the other.
enum LibraryKey {
    /// Crockford-style alphabet: no I, L, O, 0 or 1, so a key read aloud or
    /// off a screen can't be mistyped.
    static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    static let length = 24

    static func generate() -> String {
        String((0 ..< length).map { _ in alphabet.randomElement()! })
    }

    /// Accepts a key as the user typed it — any case, with or without the
    /// dashes `formatted` adds — and returns the canonical form, or `nil`
    /// when it isn't a valid key.
    static func normalize(_ input: String) -> String? {
        let allowed = Set(alphabet)
        let cleaned = input.uppercased().filter { allowed.contains($0) }
        let stripped = input.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard cleaned.count == length, stripped.count == length else { return nil }
        return cleaned
    }

    /// `ABCD-EFGH-…`, for showing and copying.
    static func formatted(_ key: String) -> String {
        stride(from: 0, to: key.count, by: 4).map { start in
            let lower = key.index(key.startIndex, offsetBy: start)
            let upper = key.index(lower, offsetBy: 4, limitedBy: key.endIndex) ?? key.endIndex
            return String(key[lower ..< upper])
        }
        .joined(separator: "-")
    }
}

/// What the sync engine remembers between launches. Kept out of SwiftData
/// so bookkeeping never dirties the library itself.
@MainActor
final class SyncState {
    private let defaults: UserDefaults

    private enum Key {
        static let libraryKey = "sync.libraryKey"
        static let deviceID = "sync.deviceID"
        static let appliedRevisions = "sync.appliedRevisions"
        static let pendingUpserts = "sync.pendingUpserts"
        static let pendingDeletes = "sync.pendingDeletes"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appliedRevisions = defaults.dictionary(forKey: Key.appliedRevisions) as? [String: Int] ?? [:]
        pendingUpserts = Set(defaults.stringArray(forKey: Key.pendingUpserts) ?? [])
        pendingDeletes = Set(defaults.stringArray(forKey: Key.pendingDeletes) ?? [])
    }

    var libraryKey: String? {
        get { defaults.string(forKey: Key.libraryKey) }
        set { defaults.set(newValue, forKey: Key.libraryKey) }
    }

    /// Identifies this install in the documents it writes; only shown in
    /// the backend console.
    var deviceID: String {
        if let id = defaults.string(forKey: Key.deviceID) {
            return id
        }
        let id = UUID().uuidString
        defaults.set(id, forKey: Key.deviceID)
        return id
    }

    /// Per series: the revision this device last applied or wrote. A
    /// remote document with the same revision is one we've already seen.
    var appliedRevisions: [String: Int] {
        didSet { defaults.set(appliedRevisions, forKey: Key.appliedRevisions) }
    }

    /// Series changed locally and not yet handed to the backend. Persisted
    /// so a change made right before quitting still goes out next launch.
    var pendingUpserts: Set<String> {
        didSet { defaults.set(Array(pendingUpserts), forKey: Key.pendingUpserts) }
    }

    var pendingDeletes: Set<String> {
        didSet { defaults.set(Array(pendingDeletes), forKey: Key.pendingDeletes) }
    }

    /// Forgets everything tied to the current library, for when the key
    /// changes. Pending local changes are dropped too: they'll be re-sent
    /// by the full push that follows a new connection.
    func resetLibraryBookkeeping() {
        appliedRevisions = [:]
        pendingUpserts = []
        pendingDeletes = []
    }
}
