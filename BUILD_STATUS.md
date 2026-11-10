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

## Phase 3 radial picker prototype

Implemented: input-specific planned choices, mixed-input intersection, radial hover/center labels, ring-segment drop capture, an exact-once selection session, and display-aware positioning. The UI explicitly says PREVIEW ONLY and acknowledges the selected target without conversion or filesystem writes.

Verified: build/signature checks plus all previous checks. New checks cover contextual and unknown-input choices, changed-payload rejection, repeated drop rejection, batch requests, clockwise segment mapping, center/outside/gap rejection, single/empty wheels, small screens, and negative display coordinates.

Pending: visual review and live drag/drop on Desktop/Finder, including timing and permissions. Phase 2's graphical gate remains open; Phase 3 was implemented provisionally after the user's next-phase instruction. Phase 4 connects the picker to engine availability.

Conversion engines and mascot animations are not active yet.


## Phase 4 conversion workers

The picker and queue share the engine registry. Jobs run with bounded concurrency, validate a staged output, and publish a unique sibling copy using an atomic hard link. This publication method requires a volume that supports hard links. Each engine currently produces one file per request.

The subprocess runner passes argument arrays directly and polls `waitpid` for exit status. On cancellation or timeout it signals the child process group and reaps the leader. This replaces the Foundation process wait that intermittently stalled during testing. In-process engines must cooperate with task cancellation.

Automated checks cover fixture conversions, missing engines and inputs, invalid outputs, duplicate jobs, concurrent name collisions, cleanup, timeouts, and cancellation. Real subprocess checks exercise literal arguments, nonzero exits, timeouts, and cancellation. The default registry is empty until Phase 5 adds a document engine. Graphical acceptance remains pending.
