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

#if os(Linux)
// Linux: the same Core, UI strings and CLI, plus a GTK/AppIndicator panel app in place of
// the AppKit one. Everything above stays the macOS package verbatim; this block only
// subtracts what cannot exist on Linux and adds what replaces it.
package.targets.removeAll { ["WhereAmIPApp", "WhereAmIPE2ETests"].contains($0.name) }
package.products.removeAll { $0.name == "WhereAmIPApp" }
for target in package.targets {
    switch target.name {
    case "whereamip-cli":
        // `-sectcreate __TEXT __info_plist` is a Mach-O section; ELF has nothing to put it in.
        target.linkerSettings = nil
    case "WhereAmIPCore":
        target.dependencies.append("CLinuxSupport")
    case "WhereAmIPUITests":
        // These exercise AppKit views and NSMenu trees, which do not exist here; the rules
        // they cover are platform-neutral and stay covered by the macOS CI run.
        target.exclude += ["BadgePillTests.swift", "HelpLinkTests.swift", "MenuBuilderTests.swift",
                           "MenuTrackingSessionTests.swift", "MenuWidthReserveTests.swift",
                           "ReadingLabelTests.swift", "WelcomeContentTests.swift", "WelcomeLayoutTests.swift"]
    default:
        break
    }
}
package.products += [
    .executable(name: "whereamip-indicator", targets: ["whereamip-indicator"]),
]
package.targets += [
    // glibc's resolver (DNS egress probe) and netlink (network-change events).
    .target(name: "CLinuxSupport", linkerSettings: [.linkedLibrary("resolv")]),
    .systemLibrary(name: "CGtk", pkgConfig: "ayatana-appindicator3-0.1",
                   providers: [.apt(["libgtk-3-dev", "libayatana-appindicator3-dev"])]),
    // The panel menu as data, the icon decision, and the Linux-only copy — everything the
    // GTK layer shows, testable without a display.
    .target(name: "WhereAmIPLinuxUI", dependencies: ["WhereAmIPCore", "WhereAmIPUI"],
            resources: [.copy("Resources/help"), .copy("Resources/welcome")]),
    .executableTarget(name: "whereamip-indicator",
                      dependencies: ["WhereAmIPCore", "WhereAmIPUI", "WhereAmIPLinuxUI", "CGtk", "CLinuxSupport"]),
    .testTarget(name: "WhereAmIPLinuxTests", dependencies: ["WhereAmIPCore", "WhereAmIPUI", "WhereAmIPLinuxUI"]),
]
#endif
