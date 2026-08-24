// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "whereamip",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WhereAmIPCore", targets: ["WhereAmIPCore"]),
        .library(name: "WhereAmIPUI", targets: ["WhereAmIPUI"]),
        .executable(name: "whereamip", targets: ["whereamip-cli"]),
        .executable(name: "WhereAmIPApp", targets: ["WhereAmIPApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(name: "WhereAmIPCore", resources: [.copy("Resources")]),
        .target(name: "WhereAmIPUI", dependencies: ["WhereAmIPCore"], resources: [.copy("Resources/flags"), .copy("Resources/welcome"),
                                       .copy("Resources/help"),
                                       .process("Resources/en.lproj"),
                                       .process("Resources/de.lproj")]),
        .executableTarget(name: "whereamip-cli",
                          dependencies: ["WhereAmIPCore",
                                         .product(name: "ArgumentParser", package: "swift-argument-parser")],
                          exclude: ["Info.plist"],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                                                          "-Xlinker", "__info_plist", "-Xlinker", "Sources/whereamip-cli/Info.plist"])]),
        .executableTarget(name: "WhereAmIPApp", dependencies: ["WhereAmIPCore", "WhereAmIPUI"]),
        .testTarget(name: "WhereAmIPCoreTests", dependencies: ["WhereAmIPCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "WhereAmIPUITests", dependencies: ["WhereAmIPUI"]),
        .testTarget(name: "WhereAmIPE2ETests", dependencies: ["WhereAmIPCore"]),
    ]
)
