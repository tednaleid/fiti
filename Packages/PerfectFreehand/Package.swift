// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PerfectFreehand",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PerfectFreehand", targets: ["PerfectFreehand"])
    ],
    targets: [
        .target(name: "PerfectFreehand", path: "Sources/PerfectFreehand"),
        .testTarget(
            name: "PerfectFreehandTests",
            dependencies: ["PerfectFreehand"],
            path: "Tests/PerfectFreehandTests",
            exclude: [
                "Fixtures/regenerate.ts",
                "Fixtures/package.json",
                "Fixtures/tsconfig.json",
                "Fixtures/node_modules",
                "Fixtures/bun.lock",
                "Fixtures/bun.lockb"
            ],
            resources: [.copy("Fixtures")]
        )
    ]
)
