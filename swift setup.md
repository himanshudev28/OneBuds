I want to build a personal macOS app in Swift using VS Code instead of Xcode. 
I am NOT publishing to the App Store; this is only for use on my own Mac.

Important constraint: my Mac has only about 13 GB of free disk space. 
Do NOT install full Xcode or any large tools. Ask me before deleting 
anything or installing anything besides what's listed below.

Please do the following, step by step, and check each step worked before 
moving on:

1. Check free disk space and my macOS version, and tell me what you find.

2. Check if Apple's Command Line Tools are installed (`xcode-select -p` 
   and `swift --version`). If not, run `xcode-select --install` and tell 
   me to click through the install dialog that appears, then wait for me 
   to confirm it finished.

3. If VS Code's `code` command is available, install the official Swift 
   extension (swiftlang.swift-vscode). If `code` isn't available, tell me 
   how to enable it instead of installing anything else.

4. Create a Swift Package Manager project in ~/Developer/MyApp with:
   - Package.swift: an executableTarget named MyApp, platform macOS 14 
     (or lower if my macOS version requires it)
   - Sources/MyApp/MyApp.swift: a simple SwiftUI app with a window showing 
     some text and a button that counts clicks. Include 
     NSApplication.shared.setActivationPolicy(.regular) so it behaves 
     like a normal app when launched with `swift run`.
   - Info.plist with CFBundleExecutable, CFBundleIdentifier 
     (com.local.myapp), CFBundleName, CFBundlePackageType (APPL), and 
     LSMinimumSystemVersion.
   - A .gitignore that ignores .build/ and *.app

5. Create an executable script build.sh in the project that:
   - runs `swift build -c release` and stops if it fails
   - assembles MyApp.app/Contents/MacOS/ and Contents/Info.plist
   - ad-hoc signs it with `codesign --force --sign - MyApp.app`
   - removes any old /Applications/MyApp.app and copies the new one there
   - prints a success message

6. Run `swift build` to confirm it compiles, then run ./build.sh and 
   confirm /Applications/MyApp.app exists. Open it with `open` to test.

7. At the end, give me a short summary of: how to run the app while 
   developing (`swift run`), how to install/update it (`./build.sh`), 
   how much disk space was used, and how to clear build caches if I'm 
   low on space later.
   