// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LorvexApple",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .visionOS(.v2),
        .watchOS(.v11)
    ],
    products: [
        .library(name: "LorvexCore", targets: ["LorvexCore"]),
        .library(name: "LorvexCloudSync", targets: ["LorvexCloudSync"]),
        .library(name: "LorvexMarkdownUI", targets: ["LorvexMarkdownUI"]),
        .library(name: "LorvexMobile", targets: ["LorvexMobile"]),
        .library(name: "LorvexSystemIntents", targets: ["LorvexSystemIntents"]),
        .library(name: "LorvexWidgetKitSupport", targets: ["LorvexWidgetKitSupport"]),
        .library(name: "LorvexWidgetIntents", targets: ["LorvexWidgetIntents"]),
        .library(name: "LorvexWidgetViews", targets: ["LorvexWidgetViews"]),
        .library(name: "LorvexWidgetExtension", targets: ["LorvexWidgetExtension"]),
        .library(name: "LorvexCarPlay", targets: ["LorvexCarPlay"]),
        .library(name: "LorvexWatch", targets: ["LorvexWatch"]),
        .executable(name: "LorvexApple", targets: ["LorvexApple"]),
        .executable(name: "LorvexMobileApp", targets: ["LorvexMobileApp"]),
        .executable(name: "LorvexVisionApp", targets: ["LorvexVisionApp"]),
        .executable(name: "LorvexWidgetBundle", targets: ["LorvexWidgetBundle"]),
        .executable(name: "LorvexFocusWidget", targets: ["LorvexFocusWidget"]),
        .executable(name: "LorvexMCPHost", targets: ["LorvexMCPHost"]),
        .executable(name: "LorvexWatchApp", targets: ["LorvexWatchApp"]),
        .executable(name: "LorvexWatchComplication", targets: ["LorvexWatchComplication"])
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.8.0"),
        // The pure-Swift core (LorvexDomain/Store/Workflow/Sync/Runtime). The app
        // talks to it through LorvexCoreServicing, implemented by
        // SwiftLorvexCoreService.
        .package(path: "core")
    ],
    targets: [
        .target(
            name: "LorvexCore",
            dependencies: [
                .product(name: "LorvexDomain", package: "core"),
                .product(name: "LorvexStore", package: "core"),
                .product(name: "LorvexWorkflow", package: "core"),
                .product(name: "LorvexSync", package: "core"),
                .product(name: "LorvexRuntime", package: "core")
            ],
            // The authoritative DDL, the migration checksum lock, and the
            // Migrations/ ladder directory are bundled so the production Swift core
            // can apply the schema, stamp/verify the `schema_migrations`
            // bookkeeping, and run the versioned-migration ladder with no env var
            // or repo checkout. All are kept byte-identical to their Apple-owned
            // authorities (`schema/schema.sql`, `schema/migrations/`) by
            // `apps/apple/script/verify_schema_embed.sh`.
            //
            // ACKNOWLEDGMENTS.md is the aggregated third-party notices document
            // (script/generate_acknowledgments.py, gated by
            // script/verify_acknowledgments.py) bundled here because LorvexCore is
            // the one target every app surface (macOS, iOS/iPadOS, visionOS) links.
            // PRIVACY_SUMMARY.md is the in-app privacy summary mirroring the
            // repository-root PRIVACY.md, bundled the same way for the same reason.
            resources: [
                .copy("Resources/schema.sql"),
                .copy("Resources/checksums.lock"),
                .copy("Resources/Migrations"),
                .copy("Resources/ACKNOWLEDGMENTS.md"),
                .copy("Resources/PRIVACY_SUMMARY.md")
            ]
        ),
        .target(
            name: "LorvexMarkdownUI",
            dependencies: [
                "LorvexCore",
                .product(name: "Markdown", package: "swift-markdown")
            ]
        ),
        .target(
            name: "LorvexCloudSync",
            dependencies: [
                "LorvexCore",
                .product(name: "LorvexSync", package: "core"),
                .product(name: "LorvexDomain", package: "core")
            ]
        ),
        .target(
            name: "LorvexWidgetKitSupport",
            dependencies: ["LorvexCore"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "LorvexWidgetIntents",
            dependencies: ["LorvexCore", "LorvexWidgetKitSupport"]
        ),
        .target(
            name: "LorvexWidgetViews",
            dependencies: ["LorvexCore", "LorvexWidgetKitSupport", "LorvexWidgetIntents"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "LorvexWidgetExtension",
            dependencies: ["LorvexCore", "LorvexWidgetKitSupport", "LorvexWidgetViews", "LorvexWidgetIntents"]
        ),
        .target(
            name: "LorvexMobile",
            dependencies: [
                "LorvexCore",
                "LorvexCloudSync",
                "LorvexMarkdownUI",
                "LorvexWidgetKitSupport",
                // MobileSettingsSections handles CloudTraversalAccountBinding
                // values surfaced by LorvexCloudSync; the type is defined in
                // LorvexSync. SwiftPM links it transitively, but the XcodeGen
                // framework build needs it declared so the iOS archive links
                // LorvexSync's type metadata (Package.swift stays in sync).
                .product(name: "LorvexSync", package: "core"),
            ],
            resources: [.process("Resources")]
        ),
        .target(
            name: "LorvexSystemIntents",
            dependencies: ["LorvexCore", "LorvexWidgetKitSupport"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "LorvexCarPlay",
            dependencies: ["LorvexCore"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "LorvexWatch",
            dependencies: ["LorvexCore", "LorvexWidgetKitSupport"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "LorvexApple",
            dependencies: [
                "LorvexCore",
                "LorvexCloudSync",
                "LorvexMarkdownUI",
                "LorvexSystemIntents",
                "LorvexWidgetKitSupport",
            ],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "LorvexMobileApp",
            dependencies: [
                "LorvexCore",
                "LorvexMobile",
                "LorvexCloudSync",
                "LorvexSystemIntents",
                // Lets a DEBUG launch flag host the real WidgetKit views in-app for
                // visual QA (simctl can't screenshot live widgets; ImageRenderer
                // can't materialize their Link/Button(intent:) rows).
                "LorvexWidgetViews"
            ]
        ),
        .executableTarget(
            name: "LorvexVisionApp",
            dependencies: [
                "LorvexCore",
                "LorvexMobile",
                "LorvexCloudSync",
                "LorvexSystemIntents"
            ]
        ),
        .executableTarget(
            name: "LorvexWidgetBundle",
            dependencies: [
                "LorvexWidgetExtension"
            ]
        ),
        .executableTarget(
            name: "LorvexFocusWidget",
            dependencies: [
                "LorvexWidgetExtension",
                "LorvexWidgetKitSupport"
            ],
            // An app extension's Mach-O entry point must be `_NSExtensionMain`,
            // not the `_main` a plain executable target links (App Store reject
            // ITMS-90898). Xcode passes this for extension targets; the
            // pure-SwiftPM macOS build must request it explicitly. NSExtensionMain
            // (Foundation) bootstraps the extension from its Info.plist
            // NSExtensionPointIdentifier and hands off to the @main WidgetBundle.
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])
            ]
        ),
        .executableTarget(
            name: "LorvexMCPHost",
            dependencies: [
                "LorvexCore",
                .product(name: "MCP", package: "swift-sdk")
            ]
        ),
        .executableTarget(
            name: "LorvexWatchApp",
            dependencies: ["LorvexWatch"]
        ),
        .executableTarget(
            name: "LorvexWatchComplication",
            dependencies: ["LorvexWatch"]
        ),
        .testTarget(
            name: "LorvexAppleTests",
            dependencies: [
                "LorvexApple",
                "LorvexCloudSync",
                "LorvexCore",
                "LorvexMarkdownUI",
                "LorvexMobile",
                .product(name: "Markdown", package: "swift-markdown"),
                "LorvexSystemIntents",
                "LorvexMCPHost",
                "LorvexWidgetExtension",
                "LorvexWidgetIntents",
                "LorvexWidgetKitSupport",
                "LorvexWidgetViews",
                "LorvexWatch",
                "LorvexWatchComplication",
                "LorvexCarPlay",
                .product(name: "LorvexSync", package: "core"),
                .product(name: "LorvexDomain", package: "core"),
                .product(name: "LorvexStore", package: "core"),
                .product(name: "MCP", package: "swift-sdk")
            ]
        ),
        .testTarget(
            name: "LorvexCoreServiceTests",
            dependencies: [
                "LorvexCore",
                .product(name: "LorvexDomain", package: "core"),
                .product(name: "LorvexStore", package: "core"),
                .product(name: "LorvexSync", package: "core"),
                .product(name: "LorvexWorkflow", package: "core"),
                .product(name: "LorvexRuntime", package: "core")
            ]
        )
    ]
)
