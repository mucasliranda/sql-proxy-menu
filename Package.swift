// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SQLProxyMenu",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SQLProxyMenu",
            path: "Sources/SQLProxyMenu"
        )
    ]
)
