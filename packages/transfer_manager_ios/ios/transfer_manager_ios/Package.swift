// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "transfer_manager_ios",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(
            name: "transfer-manager-ios",
            targets: ["transfer_manager_ios"]
        )
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "transfer_manager_ios",
            dependencies: [
                .product(
                    name: "FlutterFramework",
                    package: "FlutterFramework"
                )
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
