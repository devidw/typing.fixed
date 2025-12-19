// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FixedCursor",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "FixedCursor",
            path: "FixedCursor",
            exclude: ["Info.plist", "FixedCursor.entitlements"],
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices")
            ]
        )
    ]
)
