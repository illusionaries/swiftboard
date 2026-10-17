// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftBoardKit",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(name: "SwiftBoardKit", targets: ["SwiftBoardKit"]),
        .executable(name: "bbprobe", targets: ["bbprobe"])
    ],
    targets: [
        .target(name: "SwiftBoardKit"),
        .executableTarget(name: "bbprobe", dependencies: ["SwiftBoardKit"]),
        .testTarget(name: "SwiftBoardKitTests", dependencies: ["SwiftBoardKit"])
    ]
)
