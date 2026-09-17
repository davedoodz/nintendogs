// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nintendogs",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PetKit", path: "Sources/PetKit"),
        .executableTarget(
            name: "Nintendogs",
            dependencies: ["PetKit"],
            path: "Sources/Nintendogs"
        ),
        .testTarget(name: "PetKitTests", dependencies: ["PetKit"], path: "Tests/PetKitTests"),
        .testTarget(
            name: "NintendogsTests",
            dependencies: ["Nintendogs"],
            path: "Tests/NintendogsTests"
        ),
    ]
)
