# Phase 1 verification

Implemented: Swift 6 package, AppKit accessory application, menu-bar quit control, shared conversion request/result/engine types, generated placeholder icon, and reproducible local build/check scripts.

Verified on macOS 26.6.2 arm64:
- Release compilation and app bundle packaging.
- Info.plist validity, macOS 15 minimum deployment target, and arm64 executable.
- Ad-hoc code signature verification.
- Core checks: filename aliases and canonical extensions; remote/unknown input rejection; Unicode and spaces in local paths; distinct job IDs.

Debugged toolchain constraints:
- Selected SwiftPM's native backend and omitted debug symbols after restricted dSYM generation failed.
- Used standalone executable checks because XCTest and Testing macro plugins are unavailable in the installed Command Line Tools setup.
- Generated the ICNS container from exact-size PNG representations after iconutil rejected the icon set in this environment.

Pending acceptance: graphical background launch. The smoke test process aborts in macOS HIServices `_RegisterApplication` while initializing NSApplication, before the app delegate runs. No successful visual launch is claimed.

From a normal logged-in Mac terminal:

```sh
./scripts/build.sh
./dist/OpenLorikeet.app/Contents/MacOS/OpenLorikeet --smoke-test
open dist/OpenLorikeet.app
```

Expected: smoke test prints PASS and exits; ordinary launch shows a menu-bar bird (or OL fallback), no Dock icon, and no main window. Verify Quit works. Phase 1's final launch check remains open until this succeeds.

Conversion engines, Shift-drag interaction, and mascot animations belong to later phases and are not active yet.
