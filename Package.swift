// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Cellular-Modem-Monitor",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CellularModemMonitor", targets: ["SignalStatus"])
    ],
    targets: [
        .executableTarget(
            name: "SignalStatus",
            path: "Sources/SignalStatus"
        ),
        .testTarget(
            name: "SignalStatusTests",
            dependencies: ["SignalStatus"],
            path: "Tests/SignalStatusTests"
        )
    ]
)
