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
        // Capped below 1.8: the 1.8.x series declares swift-tools 6.0 and fails to
        // COMPILE under Xcode 16.2's Swift 6.0.3 ("reference to static property
        // 'arguments' is not concurrency-safe", Platform.swift:16) — found by the
        // MacPorts three-OS CI on macOS 14, and it equally breaks every Homebrew
        // from-source build on that toolchain. Raise the cap only alongside a
        // toolchain-floor decision, and prove it on an Xcode 16.2 builder first.
        .package(url: "https://github.com/apple/swift-argument-parser", "1.3.0"..<"1.8.0"),
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
