# Third-party notices

OneBuds contains **no third-party source code** and has **no third-party dependencies**. It uses only Apple system frameworks: SwiftUI, AppKit, Core Bluetooth, IOBluetooth, ServiceManagement, CryptoKit, and Swift Testing for tests.

All protocol code was written independently from protocol facts (UUIDs, command identifiers, byte layouts, model parameters). Those facts, and the projects they came from, are recorded with licences and revisions in [Documentation/ProtocolSources.md](Documentation/ProtocolSources.md). No code was copied from GPL-, AGPL- or unlicensed projects.

The two MIT-licensed references, Zeno-cc/OPPO-Earbuds-Mac-Controller (© 2026 Aniket Budhwani) and vedatkilic/galaxy-buds-mac (© 2026 Vedat Kılıç), informed the IOBluetooth handling, as documented in ProtocolSources §8. None of their code is included. If code from either project is ever adapted, its MIT notice will be reproduced here and in the affected files.
