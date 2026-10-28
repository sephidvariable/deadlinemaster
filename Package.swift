// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DeadlineMaster",
    platforms: [.macOS("27.0")],
    products: [.executable(name: "DeadlineMaster", targets: ["DeadlineMaster"])],
    targets: [
        .target(name: "DeadlineCore"),
        .target(name: "DeadlineAudio", dependencies: ["DeadlineCore"]),
        .executableTarget(name: "DeadlineMaster", dependencies: ["DeadlineCore", "DeadlineAudio"]),
        .testTarget(name: "DeadlineCoreTests", dependencies: ["DeadlineCore"]),
        .testTarget(name: "DeadlineAudioTests", dependencies: ["DeadlineAudio", "DeadlineCore"])
    ]
)
