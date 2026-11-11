# Finder and Desktop acceptance

## Behavior
The background app samples left-button state, modifiers, and the drag pasteboard at 30 Hz. A fresh file drag plus Shift reveals a radial format picker near the pointer. Command during a PDF drag opens the PDF tools wheel. The wheel stays anchored so the pointer can move onto a segment. Its frame is clamped to the selected display. Releasing the modifier or dropping outside dismisses it.

The picker lists formats and actions supported by ready engines across the selected files. Dropping on a segment submits the requests. The top-edge panel shows the job status and offers Open or Show in Finder once a validated output is saved. Feathers fall after a successful batch when celebrations are enabled and Reduce Motion is off. Folders, web URLs, text drags, and unavailable files are rejected.

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
4. Move onto a segment and confirm the highlight, center label, and lorikeet update. Release with Shift held and check that one conversion is submitted. Drops in the center or gaps should dismiss without a job. Check the output beside the source and try Open and Show in Finder.
5. Drop outside the target: it hides. Repeat rapidly and verify stale pasteboard contents do not cause false activation on Shift-click.
6. Repeat inside Finder, with multiple files, and at each display edge on multiple displays.
7. Try dragging text, web links, folders, and Finder selection rectangles: no target.
8. Cancel with Escape, with and without pre-existing Accessibility trust. Confirm no stuck overlay after mouse/Shift release. Escape may remain unavailable globally without trust.
9. Test successful, failed, cancelled, and mixed-result batches. Toggle feather celebrations and Reduce Motion. Confirm only successful batches celebrate.
10. Try Launch at login from the menu after installing the app. Quit using the menu bar and check that active jobs are cancelled.
11. Command-drag one PDF and confirm Compress, Metadata, Organize, and Split. Edit the title and verify it in the saved copy. Organize a multipage PDF with a list such as `3, 1` and check that the omitted page is absent. Repeat with multiple PDFs and check Merge.
12. Choose **Convert Files…** from the menu bar, select a DOCX, and save a PDF. Compare tables and images in the output with the source. Verify the 3D lorikeet responds to hover and conversion results, and stays still with Reduce Motion.

Automated checks cover gesture-state transitions and release/cancellation suppression. They do not establish real Finder drag delivery, modifier visibility under privacy controls, or AppKit drop callback timing. Record these results before distribution.
