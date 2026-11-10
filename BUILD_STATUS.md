# Build and verification status

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

## Phase 2 prototype

Implemented: fresh drag-pasteboard detection, read-only Shift/button polling, a nonactivating temporary file-drop panel, two-second drop acknowledgement, and monitor/timer cleanup. No file conversion is performed.

Verified: release build, bundle/signature checks, and automated gesture-state checks for stale pasteboard, Shift transitions, cancellation suppression, mouse release, non-file drags, and launching mid-drag. Existing core checks still pass.

Pending: actual Desktop/Finder gesture delivery, OS privacy behavior, Escape handling, and drop callback ordering. See [gesture testing](docs/GESTURE_TESTING.md). The existing graphical-launch environment restriction remains. Phase 2 is not marked fully accepted.

Conversion engines, the radial wheel, and mascot animations are not active yet.
