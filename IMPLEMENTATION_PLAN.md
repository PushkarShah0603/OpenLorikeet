# OpenLorikeet — Phased Implementation Plan

Status: implementation spans Phases 01–17. [Verification status](BUILD_STATUS.md) records open graphical, engine, and distribution checks. Complete each phase’s checks before marking it done.

## Product agreement
- Background menu-bar/tray utility; no dashboard or main application window. The initial implementation is native macOS; the user-authorized Windows/Linux expansion lives in `desktop/` with the same wheel and mascot. See docs/CROSS_PLATFORM.md for availability and gesture differences.
- Drag files on the Desktop or in Finder, hold **Shift**, hover a radial format segment, and release to convert.
- Match the recorded experience: contextual wheel, hovered format in its center, compact notch feedback, and **Open / Show in Finder** on completion. Provide a top-edge fallback on displays without a notch.
- Include an animated lorikeet companion that watches the interaction and reacts to conversion state; celebrate verified success with a short falling-feather effect.
- Save converted copies beside originals. Never silently overwrite files.
- All conversion stays local; install dependencies explicitly and verify offline operation. Fast access does not imply instant processing of large files.
- Independent implementation with OpenLorikeet branding. Review licensing before reusing upstream code or bundling engines.
- Commit verified major milestones as `Pushkar <shahpushkar0603@gmail.com>`. The user will push. No AI co-author trailers or added collaborators.

## Planned format coverage
| Input | Outputs / actions |
|---|---|
| DOCX | PDF, TXT, HTML, ODT, Markdown, LaTeX |
| PDF | Editable DOCX, TXT, JPG, PNG; merge and split |
| CSV / TSV | XLSX, PDF; CSV ↔ TSV |
| XLSX | PDF, CSV, TSV; separate text output per sheet |
| Markdown | HTML, DOCX, LaTeX, PDF |
| LaTeX project | PDF with equations, citations, references, and included files |
| JPG / PNG / HEIC | Compatible image formats, compression, resizing, PDF |
| JPG / PNG | DOCX containing the image, matching the recorded operation |

Only expose implemented routes with available engines. Image → DOCX embeds an image; OCR and editable text are separate features. PDF → DOCX is best-effort reconstruction, not guaranteed layout equivalence. PDF → original LaTeX is outside the initial scope.

## Small implementation phases

### Phase 01 — Project foundation
- [x] Create the Swift/AppKit app structure, shared conversion core, and reproducible build command.
- [x] Confirm the target Mac’s OS/architecture and choose the minimum supported macOS version. Target: macOS 15+, native architecture; development Mac: macOS 26.6.2, arm64.
- [x] Add a placeholder icon; the final icon must not block development.
**Done when:** the app builds and starts as a background utility without a main window.

Verification: build, bundle metadata, ad-hoc signature, and core checks pass. Graphical launch is pending: this execution environment aborts inside macOS `_RegisterApplication` before the app delegate runs. See [build status](BUILD_STATUS.md).

### Phase 02 — Prove Shift-drag detection
- [x] Implement the file-drag/Shift detection prototype; verify real Finder interaction in a graphical session.
- [ ] Verify required macOS permissions on the running Mac; documented API requirements and the optional trusted global Escape monitor.
- [x] Implement mouse/Shift release, cancellation suppression, and non-file filtering; real Escape behavior remains an acceptance check.
**Done when:** the gesture reliably shows and dismisses a temporary drop target on the Desktop and in Finder. Resolve this feasibility gate before polishing the wheel.

Build and automated state checks pass. Graphical acceptance is still pending; see [gesture test instructions](docs/GESTURE_TESTING.md).

### Phase 03 — Radial picker
- [x] Build the prototype wheel around the pointer, with input-specific planned choices and a central hover label.
- [x] Implement segment drop capture and center/gap/outside rejection; existing release/Escape cancellation remains subject to graphical checks.
- [x] Implement display-aware frame clamping; automated checks cover negative screen origins and small displays.
**Done when:** the chosen file and output format reach the conversion core exactly once.

Automated checks verify exact-once request capture and geometry; live drag delivery and appearance remain pending. This is a preview-only prototype authorized after Phase 2, not a claim that its graphical feasibility gate passed. Phase 04 connects the picker to engine availability.

### Phase 04 — Conversion registry and workers
- [x] Define one request/result interface and one registry for supported routes and engine readiness.
- [x] Add a background queue, bounded concurrency, temporary workspaces, timeouts, and cancellation.
- [x] Reserve unique output paths, verify generated files, and publish completed copies safely.
- [x] Invoke external tools with argument arrays; collect useful errors and clean temporary files.
**Done when:** success, missing-engine, damaged-input, timeout, and filename-collision cases behave correctly.

Fixture engines and real subprocess checks verify the worker paths. Phase 05 will register the first document engine.

### Phase 05 — DOCX conversion
- [x] Integrate a local LibreOffice adapter, using isolated profiles for conversion jobs.
- [x] Implement DOCX → PDF first, then TXT, HTML, and ODT with tested export settings.
- [ ] Verify generated documents and report missing fonts or conversion failures where detectable.
**Done when:** representative DOCX files with tables, images, headers, and page breaks produce readable PDFs; every additional advertised route passes its own checks. TXT and HTML pass. LibreOffice export awaits an installed engine.

### Phase 06 — Notch feedback
- [x] Add ready, hovered-target, processing, success, failure, and cancellation states.
- [x] Connect a placeholder animated lorikeet to these states; develop its reactions alongside the conversion flow.
- [x] Provide Open / Show in Finder; dismiss successful results and retain readable errors.
- [x] Add a minimal menu-bar menu for quit and preferences; use no main window.
**Done when:** a DOCX converts end to end through the recorded gesture and feedback pattern.

### Phase 07 — Image conversion
- [x] Use ImageIO for available JPG, PNG, and HEIC input/output routes; probe encoder support.
- [x] Preserve orientation and color deliberately; handle transparency when exporting JPEG.
- [x] Add image → PDF and JPG/PNG → DOCX embedding.
**Done when:** outputs open correctly and preserve expected dimensions, orientation, and appearance.

### Phase 08 — Image compression
- [x] Add JPEG/HEIC quality presets and lossless PNG optimization, followed by optional resizing.
- [x] Add target-size compression with bounded attempts and explicit dimension/quality limits.
- [x] Report bytes saved; avoid replacing an image with a larger compressed result.
**Done when:** each format has tested compression behavior and impossible targets return a clear result.

### Phase 09 — CSV, TSV, and XLSX
- [x] Implement robust delimited-text parsing and XLSX writing; select and validate the worker/library before integration.
- [x] Preserve leading zeros, long identifiers, Unicode, quoted delimiters, and multiline cells; do not interpret CSV text as executable formulas.
- [x] Export XLSX sheets separately to CSV/TSV with collision-safe names; define formula-value handling.
**Done when:** fixture comparisons preserve intended values and malformed or ambiguous inputs report useful errors.

### Phase 10 — Spreadsheet PDF export
- [x] Implement CSV/TSV/XLSX → PDF with suitable orientation, readable column widths, repeated headings, and pagination.
- [x] Define how wide tables and multiple sheets are split across pages.
**Done when:** narrow, wide, long, and multi-sheet examples render without clipped or unreadably small content.

### Phase 11 — PDF utilities
- [x] Use PDFKit for selectable-text extraction, page images, merge, and split.
- [x] Define page ordering and output naming; handle encrypted PDFs and image-only pages explicitly.
**Done when:** page counts/order and text/image outputs match the test documents.

### Phase 12 — PDF → editable DOCX
- [ ] Benchmark local candidate engines on simple pages, tables, images, and multi-column layouts; check maintenance, packaging, and licenses.
- [x] Integrate the selected engine and expose honest fidelity limitations.
- [x] Verify editable paragraphs and tables rather than counting a page-image wrapper as editable conversion.
**Done when:** representative outputs open in a Word-compatible editor, contain editable content, and have reviewed layout results.

### Phase 13 — Local OCR
- [ ] Detect image-only PDF pages and evaluate a local OCR engine, including mixed text/scanned PDFs.
- [x] Route recognized text and layout into DOCX generation without duplicating existing text.
- [x] Make supported languages and weak recognition results clear.
**Done when:** scanned fixtures produce editable text, and OCR quality has been checked against known text. Vision recognition remains pending after the local pixel-buffer allocation failure.

### Phase 14 — Markdown and LaTeX conversion
- [x] Integrate Pandoc for DOCX ↔ Markdown/LaTeX and Markdown → HTML/DOCX.
- [ ] Test supported equations, tables, code blocks, and embedded media; keep exported assets with their document.
**Done when:** supported structures survive conversion, and unsupported formatting is documented without promises of exact layout preservation.

### Phase 15 — LaTeX compilation
- [ ] Evaluate Tectonic versus local TeX Live against real projects; select supported engines explicitly.
- [x] Compile .tex and Markdown-derived LaTeX to PDF with bibliography passes, references, images, and included files.
- [x] Keep auxiliary outputs isolated, resolve project-relative paths, disable unrestricted shell execution, and enforce timeouts.
- [ ] Preinstall/cache dependencies and surface missing packages or compilation errors.
**Done when:** multi-file projects compile correctly with networking disabled and leave sources untouched.

### Phase 16 — Batch reliability and companion animation
- [x] Support multiple files with independent progress, failures, cancellation, and output naming.
- [x] Define mixed-selection behavior: show compatible actions and clearly identify skipped files.
- [x] Implement the companion reactions below, using actual job events rather than animation timers to infer success.
- [x] Add a brief feather celebration after validated output is saved. Keep particles near the companion, ignore mouse input, clean them up automatically, and prevent overlapping batch celebrations.
- [x] Support Reduce Motion and a celebration toggle; stop animation work when hidden.
- [ ] Test repeated gestures, large files, display changes, reduced motion, and keyboard cancellation.
**Done when:** the interface stays responsive, a failed file does not prevent the rest from completing, and reactions correctly follow success, failure, cancellation, and partial batch completion.

#### Lorikeet reaction sequence
| Event | Companion reaction |
|---|---|
| Shift during a file drag | Wake, peek out, and blink; reveal the wheel |
| Hover a format | Eyes/head turn toward the selected segment; small curious tilt |
| Release onto a format | Quick nod or wing flick to acknowledge the choice |
| Conversion running | Gentle attentive loop; truthful progress remains visible |
| Output validated and saved | Happy hop/wing flutter, then a few colorful feathers drift down and fade |
| Failure | Concerned tilt beside a readable error; no success celebration |
| Cancel / abandon drag | Settle and retract quietly |
| Batch ends | One summary reaction; partial failures stay visible |

Use the notch/status panel as the companion's home. Reserve Shift alone for normal macOS behavior unless the user later requests a standalone shortcut. Keep celebrations brief (about 1–2 seconds), preserve access to result buttons, and substitute a static pose/fade with Reduce Motion. A static app icon alone is insufficient for expressive movement: prepare layered artwork or animation frames for eyes, head, wings, and feathers during branding integration.

### Phase 17 — Icon and packaging
- [x] Integrate the second supplied lorikeet icon variant and generate icon sizes.
- [x] Add optional launch at login and a dependency readiness check.
- [ ] Choose dependency distribution, include required notices, and test installation on a clean Mac.
- [x] Prepare signing/notarization for distribution when credentials are available.
**Done when:** a documented installation runs the supported conversion set offline; remaining distribution blockers are explicit.

## Milestones and commits
- **A — Core experience:** phases 01–06; Shift-drag DOCX → PDF with notch feedback.
- **B — Images:** phases 07–08; conversion, compression, and image document export.
- **C — Tables and PDFs:** phases 09–11; spreadsheet routes and PDF utilities.
- **D — Editable PDF conversion:** phases 12–13; native-text and scanned PDF → DOCX.
- **E — Technical documents:** phases 14–15; Markdown and LaTeX project support.
- **F — Usable release:** phases 16–17; batch reliability, branding, and packaging.

Run focused checks per phase; commit coherent verified work and each completed milestone. Record limitations rather than marking untested routes complete. Keep screen recordings and private samples out of Git. The user handles pushes.

## Later additions
Saved recipes, Finder Quick Actions, watch folders, and audio/video engines. Add these only after the required routes and interaction are dependable.
