// swift-tools-version:6.3
import PackageDescription

// macOS 27 floor (2026-09-14; was .v13): follows the ZoneTilerWM root package so the adapter's
// ObjC/C sources compile against the same deployment target as every consumer. This floor is
// FORK-ONLY and lives on `main`; `swift6-macos13` is the upstream PR branch (ejbills#7) and keeps
// the macOS 13 floor upstream can accept. Tools stay 6.3, Swift 6 mode.
let package = Package(
    name: "MediaRemoteAdapter",
    platforms: [
        .macOS("27.0")
    ],
    products: [
        .library(
            name: "MediaRemoteAdapter",
            type: .dynamic,
            targets: ["MediaRemoteAdapter"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MediaRemoteAdapter",
            dependencies: ["CIMediaRemote"],
            resources: [
                .copy("Resources/run.pl")
            ]
        ),
        .testTarget(
            name: "MediaRemoteAdapterTests",
            dependencies: ["MediaRemoteAdapter"]
        ),
        .target(
            name: "CIMediaRemote",
            dependencies: [],
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-fobjc-arc"])
            ],
            linkerSettings: [
                .unsafeFlags(["-framework", "Foundation"]),
                .unsafeFlags(["-framework", "AppKit"])
            ]
        )
    ]
) 