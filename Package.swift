// swift-tools-version: 6.0
// OneBuds is built with SwiftPM and Apple's Command Line Tools only (no Xcode).
// Tools version 6.0 enables the Swift 6 language mode, i.e. strict concurrency checking.
import PackageDescription

let package = Package(
    name: "OneBuds",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OneBuds", targets: ["OneBudsApp"]),
        .executable(name: "onebuds-probe", targets: ["OneBudsProbe"]),
    ],
    targets: [
        // Framework-free diagnostics model: UUID formatting, SDP values, redaction, report rendering.
        .target(name: "OneBudsDiagnostics"),

        // Framework-free OPO frame codec, command names, and reply parsers (no Bluetooth imports).
        .target(name: "OneBudsProtocol"),

        // Shared abstractions: transport protocol, profiles/registry, OPOv1 session, device manager.
        .target(name: "OneBudsCore", dependencies: ["OneBudsProtocol"]),

        // Core Bluetooth / IOBluetooth: RFCOMM and BLE transports, discovery, read-only inspectors.
        .target(
            name: "OneBudsBluetooth",
            dependencies: ["OneBudsCore", "OneBudsDiagnostics", "OneBudsProtocol"],
            linkerSettings: [.linkedFramework("CoreBluetooth"), .linkedFramework("IOBluetooth")]
        ),

        // The menu-bar app (SwiftUI). Packaged by scripts/build-app.sh as build/OneBuds.app.
        .executableTarget(
            name: "OneBudsApp",
            dependencies: ["OneBudsBluetooth", "OneBudsCore", "OneBudsDiagnostics"],
            linkerSettings: [.linkedFramework("ServiceManagement"), .linkedFramework("AppKit")]
        ),

        // Phase B diagnostic tool. Packaged as an .app bundle by scripts/build-probe.sh so macOS
        // attributes the Bluetooth permission to it rather than to the terminal. The default mode
        // is read-only; the `session` subcommand sends the approved query-only probe.
        .executableTarget(
            name: "OneBudsProbe",
            dependencies: ["OneBudsBluetooth", "OneBudsCore", "OneBudsDiagnostics", "OneBudsProtocol"],
            linkerSettings: [
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("AppKit"),
            ]
        ),

        .testTarget(name: "OneBudsDiagnosticsTests", dependencies: ["OneBudsDiagnostics"]),
        .testTarget(name: "OneBudsProtocolTests", dependencies: ["OneBudsProtocol"]),
        .testTarget(name: "OneBudsCoreTests", dependencies: ["OneBudsCore", "OneBudsProtocol"]),
        .testTarget(name: "OneBudsBluetoothTests", dependencies: ["OneBudsBluetooth", "OneBudsCore"]),
        // App-level presentation logic (connection card). Imports the executable target.
        .testTarget(name: "OneBudsAppTests", dependencies: ["OneBudsApp", "OneBudsCore"]),
    ]
)
