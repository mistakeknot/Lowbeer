// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "lowbeer-mcp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "lowbeer-mcp",
            path: "Sources"
        )
    ]
)
