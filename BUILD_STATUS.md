# Build and verification status

The app builds for macOS 15 or newer. The Apple silicon ZIP passed archive validation and fresh extraction. The extracted bundle has a valid ad-hoc signature, accessory-app metadata, and a readable 1024 px icon.

| Area | Verified in automated checks | Pending |
|---|---|---|
| Gesture and feedback | Shift and drag transitions, radial hit testing, display bounds, exact-once selection, batch state and cancellation | Live Finder and Desktop interaction, notch placement, animation appearance, and login item behavior |
| Conversion workers | Bounded concurrency, cancellation, timeouts, duplicate submissions, validation, and exclusive publication of files and folders | Running the complete flow from Finder |
| DOCX | Native TXT and escaped HTML, Unicode and corrupt input | LibreOffice PDF and ODT export and visual Word layout review |
| Images | PNG to JPG, PDF, and embedded Word image. JPEG orientation. PNG lossless compression, 500 KB target, and resize | HEIC encoder verification in a graphical session. The encoder failed its probe here, so HEIC output is hidden |
| Spreadsheets | Quoted and multiline fields, leading zeros, long IDs, literal formula text, multi-sheet exports, cached values, and readable PDF pagination | Visual review in spreadsheet and PDF viewers |
| PDF | Ordered merge, split, page images, text extraction, editable Word paragraphs and simple tables | Complex layout fidelity. Vision could not allocate an OCR pixel buffer in this environment |
| Technical documents | Tectonic offline PDF with an included chapter, equation, and resolved reference | Pandoc integration and TeX bibliography and image fixtures against a complete cache |
| Packaging | Local build, icon generation, ZIP integrity, and signature after extraction | Clean Mac GUI acceptance and Developer ID notarization |

LibreOffice and Pandoc are absent on the build Mac, so their integration checks skip. Tectonic is installed. Its cache covers the 11 pt fixture but lacks some packages used by other documents.

The graphical smoke test aborts during macOS application registration in this environment. Test the package in a normal graphical session with the [Finder checklist](docs/GESTURE_TESTING.md). OCR, HEIC, optional engine results, and graphical acceptance remain open.

## Review pass

The regression suite covers deadlines during output validation, submissions arriving after queue shutdown, late drag data, volume filename limits, rotated PDF crop geometry, and Excel escape sequences. PNG optimization processes decoded data in blocks and validates chunk checksums. The build script stages and signs a fresh app before replacing the previous bundle.

The GitHub Pages site passes static link, asset, markup, and demo behavior checks. Browser rendering remains pending because the preview host was unavailable and local headless Chromium could not initialize its sandbox. The app smoke test still aborts during graphical registration in this environment.
