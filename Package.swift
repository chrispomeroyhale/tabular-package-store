// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TabularPackageStore",
    products: [
        .library(
            name: "TabularPackageStore",
            targets: ["TabularPackageStore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/frictionlessdata/datapackage-swift.git", exact: "1.0.0"),
        .package(url: "https://github.com/chrispomeroyhale/csv-dialect-swift.git", exact: "1.0.2")
    ],
    targets: [
        .target(
            name: "TabularPackageStore",
            dependencies: [
                .product(name: "DataPackage", package: "datapackage-swift"),
                .product(name: "DialectalCSV", package: "csv-dialect-swift")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
        .testTarget(
            name: "TabularPackageStoreTests",
            dependencies: ["TabularPackageStore"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        )
    ]
)
