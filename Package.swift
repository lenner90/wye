// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Wye",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "WyeCore"),
        .executableTarget(name: "Wye", dependencies: ["WyeCore"]),
        .testTarget(name: "WyeCoreTests", dependencies: ["WyeCore"]),
    ]
)
