// swift-tools-version: 6.2
import PackageDescription

// `mangatracker`: reads the Mac app's library from the terminal. The models
// and the owned/read rules come from the app itself (symlinked from
// `Shared/` into `Sources/mangatracker/Shared`), so a filter here means
// exactly what it means in the app.
let package = Package(
    name: "mangatracker",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "mangatracker",
            swiftSettings: [
                // Same as the app targets.
                .swiftLanguageMode(.v5),
                .defaultIsolation(MainActor.self),
            ]
        ),
    ]
)
