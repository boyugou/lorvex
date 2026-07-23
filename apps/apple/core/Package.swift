// swift-tools-version: 6.0

import PackageDescription

// The pure-Swift Apple core: a faithful port of the Rust core crates
// (lorvex-domain/store/workflow/sync/runtime), with zero dependency on the app
// layer. It is the app's backend: the app package (../Package.swift) consumes
// these products via a local path dependency (`.package(path: "core")`).
//
// It is also a standalone package, so the core can be built and tested in
// isolation without the app target:
//   cd apps/apple/core && swift test
let package = Package(
    name: "LorvexAppleCore",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .visionOS(.v2),
        .watchOS(.v11)
    ],
    products: [
        .library(name: "LorvexDomain", targets: ["LorvexDomain"]),
        .library(name: "LorvexStore", targets: ["LorvexStore"]),
        .library(name: "LorvexWorkflow", targets: ["LorvexWorkflow"]),
        .library(name: "LorvexSync", targets: ["LorvexSync"]),
        .library(name: "LorvexRuntime", targets: ["LorvexRuntime"])
    ],
    dependencies: [
        // GRDB.swift — SQLite over a typed, value-oriented Swift API. Powers
        // the LorvexStore layer; the rest of the core (LorvexDomain) stays
        // dependency-free.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0")
    ],
    targets: [
        .target(name: "LorvexDomain"),
        .testTarget(name: "LorvexDomainTests", dependencies: ["LorvexDomain"]),
        .target(
            name: "LorvexStore",
            dependencies: [
                "LorvexDomain",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(name: "LorvexStoreTests", dependencies: ["LorvexStore"]),
        .target(
            name: "LorvexWorkflow",
            dependencies: [
                "LorvexDomain",
                "LorvexStore",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "LorvexWorkflowTests",
            dependencies: [
                "LorvexWorkflow",
                "LorvexDomain",
                "LorvexStore",
                "LorvexRuntime",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .target(
            name: "LorvexSync",
            dependencies: [
                "LorvexDomain",
                "LorvexStore",
                // Matches the Rust layering: `lorvex-sync` depends on
                // `lorvex-workflow` for the dependency-cycle validator
                // (`validate_no_dependency_cycle` / `find_cycle_path`) the
                // task_dependency upsert cycle-break path needs.
                "LorvexWorkflow",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            // Numbered payload manifests are executable production contracts.
            // The release gate keeps these resource copies byte-identical to
            // the Apple authority under schema/sync_payload/.
            resources: [.copy("Resources/SyncPayloadContracts")]
        ),
        .testTarget(
            name: "LorvexSyncTests",
            dependencies: [
                "LorvexSync",
                "LorvexDomain",
                "LorvexStore",
                "LorvexWorkflow",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .target(
            name: "LorvexRuntime",
            dependencies: [
                "LorvexDomain",
                "LorvexStore",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        // Performance baseline harness. Lives in its own test target so the
        // normal `swift test` run is unaffected: every benchmark method
        // skips immediately unless `LORVEX_BENCH` is set in the environment,
        // so seeding (10k+ rows) never runs during an ordinary test pass.
        //   Run: LORVEX_BENCH=1 swift test --filter Benchmark
        .testTarget(
            name: "LorvexBenchmarks",
            dependencies: [
                "LorvexDomain",
                "LorvexStore",
                "LorvexWorkflow",
                "LorvexSync",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "LorvexRuntimeTests",
            dependencies: [
                "LorvexRuntime",
                "LorvexDomain",
                "LorvexStore",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        )
    ]
)
