# OpenLorikeet

Your files. A quick shift.

A native macOS background utility being built for Shift-drag file conversion, a radial format picker, and an animated lorikeet with compact notch feedback.

## Current status
The background foundation, Shift-drag detector, and radial picker prototype are implemented. The wheel adapts planned choices to the selected inputs, highlights the hovered format, and captures a drop once. It is labeled **PREVIEW ONLY**: no conversion engines are connected and no files are modified. Real Desktop/Finder acceptance and visual verification are pending. See [gesture behavior and pending checks](docs/GESTURE_TESTING.md). See [the phased implementation plan](IMPLEMENTATION_PLAN.md).

## Build and run
Requires macOS 15 or newer and a Swift 6 toolchain from Xcode or Command Line Tools. No external Swift packages or conversion engines are required for this phase. The build targets the current Mac's architecture.

```sh
./scripts/build.sh
open dist/OpenLorikeet.app
```

The app runs without a main window or Dock icon. Find its bird icon (or `OL` fallback) in the menu bar; use **Quit OpenLorikeet** to stop it. The generated bundle is ad-hoc signed for local development, not notarized for distribution.

The scripts currently select SwiftPM’s native build backend and omit debug symbols to work around the installed toolchain’s restricted debug-symbol generation. Core checks use a standalone executable so XCTest and compiler macro plugins are not required.

## Verify
```sh
./scripts/test.sh
./dist/OpenLorikeet.app/Contents/MacOS/OpenLorikeet --smoke-test
```

The smoke test requires a logged-in graphical macOS session. It follows the real launch path, checks the accessory activation policy, verifies no windows were created and that the status item was allocated, prints a result, and exits. This does not verify the menu's visual appearance; check that manually after opening the app.

Build products and temporary files stay out of Git. Commits use the repository's configured author identity; the user handles pushes.
