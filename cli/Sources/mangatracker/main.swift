import Foundation

let usage = """
Usage: mangatracker [--list] [options] [title…]

Lists from your MangaTracker library (the Mac app's, read-only).

Series, as in the app's sidebar (default: --all):
  --all             the library: everything not sold or planned
  --in-progress     owned and not wrapped up yet
  --completed       every volume read and the series finished
  --favorites
  --planned         the wishlist
  --sold

Volumes:
  -u, --unread      owned volumes still waiting to be read
  -m, --missing     volumes not owned or on their way yet
  -o, --ordered     volumes on their way
  --upcoming        volumes with a release date from today on
  --stats           library totals

Options:
  -s, --search TEXT only series whose title contains TEXT
                    (words after the options do the same)
  --json            machine-readable output
  --store PATH      read another SwiftData store instead of the app's
  -h, --help
"""

enum Report {
    case series(LibraryCategory)
    case unread, missing, ordered, upcoming, stats
}

struct Options {
    var report = Report.series(.all)
    var search: String?
    var json = false
    var storeURL = LibrarySnapshot.defaultStoreURL

    init(_ arguments: [String]) throws {
        var chosen: String?
        var words: [String] = []
        var iterator = arguments.makeIterator()

        func choose(_ flag: String, _ report: Report) throws {
            if let chosen, chosen != flag {
                throw CLIError("Pick one list: \(chosen) or \(flag).")
            }
            chosen = flag
            self.report = report
        }

        func value(for flag: String) throws -> String {
            guard let value = iterator.next() else { throw CLIError("\(flag) needs a value.") }
            return value
        }

        while let argument = iterator.next() {
            switch argument {
            case "--all": try choose(argument, .series(.all))
            case "--in-progress": try choose(argument, .series(.inProgress))
            case "--completed": try choose(argument, .series(.completed))
            case "--favorites", "--favourites": try choose(argument, .series(.favorites))
            case "--planned": try choose(argument, .series(.planned))
            case "--sold": try choose(argument, .series(.sold))
            case "-u", "--unread": try choose(argument, .unread)
            case "-m", "--missing": try choose(argument, .missing)
            case "-o", "--ordered": try choose(argument, .ordered)
            case "--upcoming": try choose(argument, .upcoming)
            case "--stats": try choose(argument, .stats)
            case "-s", "--search": try words.append(value(for: argument))
            case "--json": json = true
            case "--store":
                storeURL = try URL(fileURLWithPath: (value(for: argument) as NSString).expandingTildeInPath)
            case "-h", "--help":
                throw HelpRequested()
            default:
                if argument.hasPrefix("-") {
                    throw CLIError("Unknown option \(argument). See mangatracker --help.")
                }
                words.append(argument)
            }
        }
        search = words.isEmpty ? nil : words.joined(separator: " ")
    }
}

struct HelpRequested: Error {}

// MARK: - Output

let useColor = isatty(STDOUT_FILENO) == 1 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil

func bold(_ text: String) -> String {
    useColor ? "\u{1B}[1m\(text)\u{1B}[0m" : text
}

func dim(_ text: String) -> String {
    useColor ? "\u{1B}[2m\(text)\u{1B}[0m" : text
}

func padded(_ text: String, to width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

/// `[1, 2, 3, 5, 7, 8]` as "1–3, 5, 7–8".
func ranges(_ numbers: [Int]) -> String {
    var parts: [String] = []
    var index = 0
    let sorted = numbers.sorted()
    while index < sorted.count {
        var end = index
        while end + 1 < sorted.count, sorted[end + 1] == sorted[end] + 1 {
            end += 1
        }
        parts.append(end == index ? "\(sorted[index])" : "\(sorted[index])–\(sorted[end])")
        index = end + 1
    }
    return parts.joined(separator: ", ")
}

func printJSON(_ value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .custom { date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(date.yyyyMMdd())
    }
    try print(String(decoding: encoder.encode(value), as: UTF8.self))
}

func printEmpty(_ message: String, json: Bool) throws {
    if json {
        print("[]")
    } else {
        print(dim(message))
    }
}

extension Manga {
    var sortedVolumes: [Volume] {
        volumes.sorted { $0.number < $1.number }
    }

    /// Not sold and not on the wishlist: what the volume lists look at.
    var isInCollection: Bool {
        !(isSold ?? false) && !(isPlanned ?? false)
    }
}

// MARK: - Reports

struct SeriesRow: Encodable {
    let title: String
    let owned: Int
    let total: Int
    let onItsWay: Int
    let readPercent: Int
    let nextUnread: Int?
}

func printSeries(_ mangas: [Manga], category: LibraryCategory, json: Bool) throws {
    let rows = mangas.compactMap { manga -> SeriesRow? in
        let stats = manga.volumeStats
        guard category.contains(manga, stats: stats) else { return nil }
        return SeriesRow(
            title: manga.title,
            owned: stats.owned,
            total: stats.total,
            onItsWay: stats.onItsWay,
            readPercent: Int(stats.readPercent.rounded()),
            nextUnread: stats.nextUnread?.number
        )
    }
    if json {
        return try printJSON(rows)
    }
    guard !rows.isEmpty else { return try printEmpty("Nothing here.", json: false) }

    let width = min(rows.map(\.title.count).max() ?? 0, 40)
    for row in rows {
        var details = ["\(row.owned)/\(row.total) owned", "\(row.readPercent)% read"]
        if row.onItsWay > 0 {
            details.append("\(row.onItsWay) on the way")
        }
        if let next = row.nextUnread {
            details.append("next: \(next)")
        }
        print("\(bold(padded(row.title, to: width)))  \(dim(details.joined(separator: " · ")))")
    }
    print(dim("\n\(rows.count) series"))
}

struct VolumeGroup: Encodable {
    struct Entry: Encodable {
        let number: Int
        /// Read parts of a split volume, as "1/3".
        let parts: String?
        let date: Date?
    }

    let title: String
    let volumes: [Entry]
}

/// One line per series: the title and the volumes `select` picks.
func printVolumeGroups(
    _ mangas: [Manga],
    json: Bool,
    empty: String,
    total: (Int) -> String,
    select: (Manga) -> [VolumeGroup.Entry]
) throws {
    let groups = mangas.compactMap { manga -> VolumeGroup? in
        let entries = select(manga)
        return entries.isEmpty ? nil : VolumeGroup(title: manga.title, volumes: entries)
    }
    if json {
        return try printJSON(groups)
    }
    guard !groups.isEmpty else { return try printEmpty(empty, json: false) }

    let width = min(groups.map { $0.title.count + 4 }.max() ?? 0, 44)
    for group in groups {
        let plain = group.volumes.filter { $0.parts == nil && $0.date == nil }.map(\.number)
        var listed = plain.isEmpty ? [] : [ranges(plain)]
        for entry in group.volumes where entry.parts != nil || entry.date != nil {
            let notes = [entry.parts.map { "\($0) parts read" }, entry.date.map { "ordered \($0.yyyyMMdd())" }].compactMap(\.self)
            listed.append("\(entry.number) \(dim("(\(notes.joined(separator: ", ")))"))")
        }
        let label = padded("\(group.title) (\(group.volumes.count))", to: width)
        print("\(bold(label))  \(listed.joined(separator: ", "))")
    }
    let count = groups.reduce(0) { $0 + $1.volumes.count }
    print(dim("\n\(total(count)) across \(groups.count) series"))
}

struct UpcomingRow: Encodable {
    let date: Date
    let title: String
    let volume: Int
    let owned: Bool
    let ordered: Bool
}

func printUpcoming(_ mangas: [Manga], json: Bool) throws {
    let today = Calendar.current.startOfDay(for: .now)
    let rows = mangas.flatMap { manga in
        manga.volumes.compactMap { volume -> UpcomingRow? in
            guard let date = volume.releaseDate, date >= today else { return nil }
            return UpcomingRow(date: date, title: manga.title, volume: volume.number, owned: volume.owned, ordered: volume.isOnItsWay)
        }
    }
    .sorted { ($0.date, $0.title, $0.volume) < ($1.date, $1.title, $1.volume) }

    if json {
        return try printJSON(rows)
    }
    guard !rows.isEmpty else { return try printEmpty("No upcoming releases.", json: false) }
    for row in rows {
        let status = row.owned ? " (owned)" : row.ordered ? " (ordered)" : ""
        print("\(dim(row.date.yyyyMMdd()))  \(bold(row.title)) \(row.volume)\(dim(status))")
    }
}

struct StatsReport: Encodable {
    let series: Int
    let ownedVolumes: Int
    let readVolumes: Int
    let unreadVolumes: Int
    let onItsWay: Int
    let missingVolumes: Int
    let readPercent: Int
    let totalPaid: Double
    let readToday: Bool
    let readStreak: Int
}

func printStats(_ mangas: [Manga], json: Bool) throws {
    let library = MangaLibraryStats(mangas: mangas)
    var read = 0, unread = 0, onItsWay = 0, missing = 0
    for manga in mangas where manga.isInCollection {
        for volume in manga.volumes {
            if volume.owned {
                if volume.read == true {
                    read += 1
                } else {
                    unread += 1
                }
            } else if volume.isOnItsWay {
                onItsWay += 1
            } else {
                missing += 1
            }
        }
    }
    let report = StatsReport(
        series: library.mangaCount,
        ownedVolumes: library.ownedVolumesCount,
        readVolumes: read,
        unreadVolumes: unread,
        onItsWay: onItsWay,
        missingVolumes: missing,
        readPercent: Int(library.totalReadPercent.rounded()),
        totalPaid: library.totalPaid,
        readToday: library.didReadToday,
        readStreak: library.currentReadStreak
    )
    if json {
        return try printJSON(report)
    }

    let paid = report.totalPaid.formatted(.currency(code: "PLN").locale(Locale(identifier: "pl_PL")))
    let lines: [(String, String)] = [
        ("Series", "\(report.series)"),
        ("Owned volumes", "\(report.ownedVolumes)"),
        ("Read", "\(report.readVolumes) (\(report.readPercent)%)"),
        ("Unread", "\(report.unreadVolumes)"),
        ("On the way", "\(report.onItsWay)"),
        ("Missing", "\(report.missingVolumes)"),
        ("Spent", paid),
        ("Read streak", "\(report.readStreak) day\(report.readStreak == 1 ? "" : "s")\(report.readToday ? ", read today" : "")"),
    ]
    for (label, value) in lines {
        print("\(dim(padded(label, to: 14)))\(bold(value))")
    }
}

// MARK: - Main

func run() throws {
    let options = try Options(Array(CommandLine.arguments.dropFirst()))
    let snapshot = try LibrarySnapshot(storeURL: options.storeURL)
    defer { snapshot.close() }

    var mangas = try snapshot.mangas()
    if let search = options.search {
        mangas = mangas.filter { $0.title.localizedStandardContains(search) }
    }
    mangas.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

    switch options.report {
    case let .series(category):
        try printSeries(mangas, category: category, json: options.json)

    case .unread:
        try printVolumeGroups(
            mangas.filter { LibraryCategory.unread.contains($0) },
            json: options.json,
            empty: "Everything you own is read.",
            total: { "\($0) unread" }
        ) { manga in
            manga.sortedVolumes.filter { $0.owned && $0.read != true }.map { volume in
                let parts = volume.isSplit && volume.readPartCount > 0 ? "\(volume.readPartCount)/\(volume.parts.count)" : nil
                return .init(number: volume.number, parts: parts, date: nil)
            }
        }

    case .missing:
        try printVolumeGroups(
            mangas.filter(\.isInCollection),
            json: options.json,
            empty: "Nothing missing.",
            total: { "\($0) missing" }
        ) { manga in
            manga.sortedVolumes.filter { !$0.owned && !$0.isOnItsWay }.map {
                .init(number: $0.number, parts: nil, date: nil)
            }
        }

    case .ordered:
        try printVolumeGroups(
            mangas.filter(\.isInCollection),
            json: options.json,
            empty: "Nothing on the way.",
            total: { "\($0) on the way" }
        ) { manga in
            manga.sortedVolumes.filter(\.isOnItsWay).map {
                .init(number: $0.number, parts: nil, date: $0.purchaseDate)
            }
        }

    case .upcoming:
        try printUpcoming(mangas, json: options.json)

    case .stats:
        try printStats(mangas, json: options.json)
    }
}

do {
    try run()
} catch is HelpRequested {
    print(usage)
} catch {
    FileHandle.standardError.write(Data("mangatracker: \(error)\n".utf8))
    exit(error is CLIError ? 2 : 1)
}
