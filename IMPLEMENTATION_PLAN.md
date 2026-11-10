# OpenLorikeet — Implementation Plan

## Goal
Build a local macOS background utility inspired by Open Tangerine: drag files in Finder, hold **Shift**, choose an action, and save converted copies beside the originals. No dashboard or main window; only a small format picker, progress indicator, and error messages. Processing stays offline. Fast access is the goal; large conversions may take time.

## Required conversions
| Input | Outputs / actions |
|---|---|
| DOCX | PDF, TXT, HTML, Markdown, LaTeX, ODT |
| PDF | Editable DOCX, TXT, PNG, JPG; merge and split |
| CSV / TSV | XLSX, PDF; CSV ↔ TSV |
| XLSX | PDF, CSV, TSV (one text file per sheet) |
| Markdown | DOCX, HTML, LaTeX, PDF |
| LaTeX | PDF with equations, citations, and project dependencies |
| JPG / PNG / HEIC | Convert, compress, resize; images → PDF |

## Interaction reference (observed in the supplied recording)
- Match the desktop drag workflow: Shift-drag reveals a radial wheel near the pointer; drag onto a format segment and release to convert.
- Adapt wheel choices to the input. Display the hovered format in the center and update a compact status panel beneath the notch.
- Use the notch panel for ready, processing, and completion states, with an OpenLorikeet mascot and **Open / Show in Finder** result actions.
- Save copies beside the source. The recording shows image → DOCX and PDF → DOCX completion; output editability/layout was not demonstrated.
- Fix the observed DOCX input dead end: `Sample.docx` displays **No conversions available** in Open Tangerine. OpenLorikeet must offer working DOCX routes.

## Implementation
1. **Prove the engines:** test real DOCX, PDF, CSV, image, and LaTeX samples before connecting the gesture.
2. **Build the core:** Swift job queue and one conversion interface. Use ImageIO for images, PDFKit for PDF utilities, LibreOffice for Office conversion, Pandoc for structured documents, and a local TeX engine for LaTeX. Evaluate a dedicated PDF-to-DOCX engine with local OCR for scans. Add a CSV/XLSX worker and lossless PNG optimizer.
3. **Add the gesture:** use AppKit for a background app and Shift-drag picker. Check macOS permission requirements early. Show only supported actions whose engines are ready; explain missing dependencies.
4. **Make jobs reliable:** background workers, timeouts, cancellation, per-file results, output validation, unique filenames, and originals preserved.
5. **Polish and package:** add simple compression presets and target-size mode, optional launch at login, a minimal quit/settings menu, and a clean-Mac installation test. Prepare signing and notarization for distribution.

## Delivery order
- **Milestone 1:** Shift-drag + DOCX → PDF + JPG/PNG/HEIC conversion and compression.
- **Milestone 2:** CSV ↔ XLSX, spreadsheet → readable PDF, PDF utilities.
- **Milestone 3:** PDF → DOCX with OCR, Markdown and LaTeX routes.
- **Later:** saved recipes, Finder Quick Actions, watch folders, and audio/video conversions.

## Acceptance checks
- Every offered route produces a readable output; missing tools produce actionable errors.
- Test document layout, editable PDF extraction, scanned pages, equations, and references. PDF → DOCX is best-effort; PDF → original LaTeX is outside the initial scope.
- Preserve CSV identifiers, leading zeros, Unicode, and quoted fields; paginate wide tables clearly.
- Test image orientation, transparency, color, size savings, and mixed batches. Report when compression cannot improve size or meet a target.
- Preinstall/cache dependencies for offline use. Test LaTeX projects with included files and bibliographies.

**Codebase decision:** prefer an independent implementation; if reusing Open Tangerine code, review and follow its GPL-3.0-only licensing. AI/RAG is not part of the agreed core scope.
