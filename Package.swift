// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "toyvm",
    platforms: [.macOS(.v12)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "ToyVMCore",
            path: "ToyVMCore"
        ),
        .executableTarget(
            name: "toyvm",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "ToyVMCore",
            ],
            path: "toyvm"
        ),
    ]
)
