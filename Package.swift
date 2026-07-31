// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ApexTerm",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ApexTerm", targets: ["ApexTermApp"]),
        .library(name: "ApexTermCore", targets: ["ApexTermCore"]),
        .executable(name: "apexterm-score", targets: ["ApexTermScore"]),
        .executable(name: "apexterm-bench", targets: ["ApexTermBench"]),
        .executable(name: "apextermctl", targets: ["ApexTermControl"]),
        .executable(name: "gag", targets: ["GagCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.14.0")
    ],
    targets: [
        .target(
            name: "ApexTermCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "ApexTermApp",
            dependencies: [
                "ApexTermCore",
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "ApexTermScore",
            dependencies: ["ApexTermCore"]
        ),
        .executableTarget(
            name: "ApexTermBench",
            dependencies: [
                "ApexTermCore",
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ]
        ),
        .executableTarget(
            name: "ApexTermControl",
            dependencies: ["ApexTermCore"]
        ),
        .executableTarget(
            name: "GagCLI",
            dependencies: ["ApexTermCore"]
        ),
        .testTarget(
            name: "ApexTermCoreTests",
            dependencies: [
                "ApexTermCore",
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ]
        )
    ]
)
