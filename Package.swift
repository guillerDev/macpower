// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacPower",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        // Thin C interop layer exposing the private IOReport symbols to Swift.
        .target(
            name: "CIOReport",
            linkerSettings: [
                .linkedLibrary("IOReport"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        // C shim for the Apple SMC key protocol (fans, temperatures, power).
        .target(
            name: "CSMC",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        // The SwiftUI application.
        .executableTarget(
            name: "MacPower",
            dependencies: ["CIOReport", "CSMC"],
            exclude: ["Info.plist"],   // consumed by the linker flag below, not a resource
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                // Embed an Info.plist into the bare executable so it has a bundle
                // identifier even when run directly (e.g. from Xcode/SwiftPM),
                // silencing App Intents / Process Registry warnings.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/MacPower/Info.plist"
                ])
            ]
        ),
        // Pure-logic tests (no SMC/IOReport hardware needed) — run anywhere.
        .testTarget(
            name: "MacPowerTests",
            dependencies: ["MacPower"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
