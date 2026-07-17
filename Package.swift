// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodeXMicro",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodeXMicro", targets: ["CodeXMicroApp"])
    ],
    targets: [
        .executableTarget(
            name: "CodeXMicroApp",
            path: "Sources/CodeXMicroApp",
            exclude: ["Resources"]
        )
    ]
)
