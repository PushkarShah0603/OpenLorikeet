# Build and verification status

The app builds for macOS 15 or newer. The Apple silicon ZIP passed archive validation and fresh extraction. The extracted bundle has a valid ad-hoc signature, accessory-app metadata, and a readable 1024 px icon.

| Area | Verified in automated checks | Pending |
|---|---|---|
| Gesture and feedback | Modifier and drag state transitions, radial hit testing, display bounds, exact-once selection, batch state and cancellation; transparent cartoon atlas and offline rendering of ready, working, happy, and failed poses | Live Finder Shift and Command drag, menu-bar file picker, live mascot animation, notch placement, and login item behavior |
| Conversion workers | Bounded concurrency, cancellation, timeouts, duplicate submissions, validation, and exclusive publication of files and folders | Running the complete flow from Finder |
| DOCX | Native PDF with tables, page breaks, repeated pictures, and compatibility textboxes. A supplied lab manual exports all 58 picture placements within page bounds. TXT and escaped HTML, Unicode and corrupt input | Exact Word pagination, floating drawing layout, and LibreOffice PDF and ODT integration |
| Images | PNG to JPG, PDF, and embedded Word image. JPEG orientation. PNG lossless compression, 500 KB target, and resize | HEIC encoder verification in a graphical session. The encoder failed its probe here, so HEIC output is hidden |
| Spreadsheets | Quoted and multiline fields, leading zeros, long IDs, literal formula text, multi-sheet exports, cached values, and readable PDF pagination | Visual review in spreadsheet and PDF viewers |
| PDF | Ordered merge, split, page images, text extraction, editable Word paragraphs and simple tables. Screen compression with selectable text, metadata round-trip, and page reordering and omission | Live PDF tool dialogs and complex layout fidelity. Vision could not allocate an OCR pixel buffer in this environment |
| Technical documents | Tectonic offline PDF with an included chapter, equation, and resolved reference | Pandoc integration and TeX bibliography and image fixtures against a complete cache |
| Packaging | Local build, icon generation, ZIP integrity, and signature after extraction | Clean Mac GUI acceptance and Developer ID notarization |

LibreOffice and Pandoc are absent on the build Mac, so their integration checks skip. Tectonic is installed. Its cache covers the 11 pt fixture but lacks some packages used by other documents.

The graphical smoke test aborts during macOS application registration in this environment. Test the package in a normal graphical session with the [Finder checklist](docs/GESTURE_TESTING.md). OCR, HEIC, optional engine results, and graphical acceptance remain open.

## Review pass

The regression suite covers deadlines during output validation, submissions arriving after queue shutdown, late drag data, volume filename limits, rotated PDF crop geometry, and Excel escape sequences. PNG optimization processes decoded data in blocks and validates chunk checksums. The build script stages and signs a fresh app before replacing the previous bundle.

The GitHub Pages site passes static link, asset, and interactive walkthrough checks, including reduced-motion timing. The local page opened in Zen. The app smoke test still aborts before reporting launch success in this environment.

## Windows and Linux expansion

`desktop/` contains the Qt tray utility, radial drop wheel, cartoon atlas animation, background workers, and a portable conversion core. Native Windows and Linux builds are configured in `.github/workflows/desktop.yml`. Their builds and graphical acceptance are pending. The local package index could not resolve, so Qt, python-docx, openpyxl and ReportLab could not be installed here. Available local Python checks verify PDF image export/merge/split/order/metadata, route gating, and collision-safe publication; Word pictures and spreadsheet checks await installed dependencies. macOS remains the native Swift build. Feature and interaction differences are listed in [CROSS_PLATFORM.md](docs/CROSS_PLATFORM.md).

## Download pipeline repair

GitHub run 43005543458 confirms Windows and Linux build/test/render jobs succeeded. Mac compilation failed in WordPictures cell-width inference; that expression is now split into typed steps and passes local regression checks. The website now resolves direct asset URLs from complete, public releases rather than presenting Actions pages as downloads. CI publishes all three packages plus checksums after all required jobs pass, and portable packages run an import/resource/render self-test before upload. Linux uses tar.gz to retain executable permissions. Remote verification of the repair awaits the next pushed build.
