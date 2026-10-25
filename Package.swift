// swift-tools-version:6.4
import PackageDescription

// macOS 27 floor (2026-09-14; was .v13): follows the ZoneTilerWM root package so the adapter's
// ObjC/C sources compile against the same deployment target as every consumer. Tools 6.4, Swift 6
// mode.
//
// Two targets, as ungive's CMake build has one library and one script:
//   - `MediaRemoteAdapterCore`: ungive/mediaremote-adapter's ObjC adapter, vendored at a pinned
//     commit under Vendor/ungive-mediaremote-adapter (VENDORED.md: the commit, the licence and
//     every local patch). Its CMake `ADAPTER_SOURCES` are exactly src/adapter, src/private and
//     src/utility; its private include root is `src`, its public one `include`.
//   - `MediaRemoteAdapter`: this fork's Swift layer. Its resource `run.pl` is the vendored
//     bin/mediaremote-adapter.pl, byte for byte (tools/repo_gates.sh holds the two equal); the
//     name is the one consumers' availability probes look for.
let package = Package(
    name: "MediaRemoteAdapter",
    platforms: [
        .macOS("27.0")
    ],
    products: [
        .library(
            name: "MediaRemoteAdapter",
            type: .dynamic,
            targets: ["MediaRemoteAdapter"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MediaRemoteAdapter",
            dependencies: ["MediaRemoteAdapterCore"],
            resources: [
                .copy("Resources/run.pl")
            ]
        ),
        .testTarget(
            name: "MediaRemoteAdapterTests",
            dependencies: ["MediaRemoteAdapter"],
            // Live captures of the vendored core (tools/record_fixtures.sh), read verbatim by
            // WireFixtures.
            resources: [
                .copy("Fixtures")
            ]
        ),
        .target(
            name: "MediaRemoteAdapterCore",
            path: "Vendor/ungive-mediaremote-adapter",
            exclude: [
                "CMakeLists.txt", "LICENSE", "README.md", "VENDORED.md", "upstream.sha256", "patches",
                "bin", "src/test"
            ],
            sources: ["src/adapter", "src/private", "src/utility"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("src")
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        )
    ]
)
