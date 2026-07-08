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
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit")
            ]
        )
    ]
)
