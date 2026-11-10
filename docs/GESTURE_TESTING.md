# Phase 2–3 interaction prototype

## Behavior
The background app samples left-button state, Shift, and the drag pasteboard at 30 Hz. A fresh file drag plus Shift reveals a radial format picker near the pointer. The wheel stays anchored so the pointer can move onto a segment. Its frame is clamped to the selected display. Shift release hides it; dropping outside also dismisses it. Normal drags and Shift-clicks with stale pasteboard contents do not activate it.

The picker now lists formats supported by ready engines across all selected files. The current build has an empty registry, so the wheel displays “No engines.” With a registered engine, dropping on a segment captures the request once and submits it to the conversion queue. Folders, web URLs, text drags, and unavailable files are rejected.

## Permissions
No permission prompt or permission change is performed by the app. The base prototype polls mouse/modifier state and reads only the drag pasteboard, not the general clipboard. Actual behavior under macOS privacy controls remains a graphical-session test.

Escape handling uses a local event monitor and, only if the application already has Accessibility trust at launch, a global key monitor. Apple documents that global key-event monitoring requires Accessibility access. Without that existing trust, global Escape cannot be guaranteed; release Shift or the mouse button to dismiss the target. Relaunch after any manually granted trust. No global keystrokes are logged or stored.

References:
- [Apple: monitoring events](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html)
- [Apple: receiving drag operations](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/DragandDrop/Tasks/acceptingdrags.html)

## Graphical acceptance checklist (pending)
1. Build with `./scripts/build.sh`, then launch `dist/OpenLorikeet.app` in a normal logged-in session.
2. Drag a real Desktop file normally: no target. Add Shift: target appears near the pointer.
3. Release Shift: target hides. Hold Shift again during the same drag: target reappears.
4. With a ready engine registered, move onto each segment: its highlight and central target label update. Release with Shift held: one target-specific receipt appears, then disappears. Drops in the center or gaps must do nothing. Confirm the source is untouched and a converted copy appears beside it.
5. Drop outside the target: it hides. Repeat rapidly and verify stale pasteboard contents do not cause false activation on Shift-click.
6. Repeat inside Finder, with multiple files, and at each display edge on multiple displays.
7. Try dragging text, web links, folders, and Finder selection rectangles: no target.
8. Cancel with Escape, with and without pre-existing Accessibility trust. Confirm no stuck overlay after mouse/Shift release. Escape may remain unavailable globally without trust.
9. Quit using the menu bar; monitoring and the temporary panel stop.

Automated checks cover gesture-state transitions and release/cancellation suppression. They do not establish real Finder drag delivery, modifier visibility under privacy controls, or AppKit drop callback timing. Resolve these checks before polishing Phase 3.
