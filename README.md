# OpenLorikeet

OpenLorikeet is a local macOS file converter. Drag a file from Finder or the Desktop, hold Shift, and drop it on an available format. The lorikeet follows the picker and celebrates after a converted copy is saved beside the original.

## Install and try

Use macOS 15 or newer. The build targets the Mac on which it runs. Build from source with Xcode or Command Line Tools and Swift 6.

```sh
./scripts/package.sh
open dist/OpenLorikeet.app
```

The ZIP in `dist/` contains the app for the current architecture. Extract it and move the app to Applications for regular use. The default build uses an ad-hoc signature for local development. The app lives in the menu bar with engine status, launch at login, feather celebrations, and Quit.

## Formats and actions

| Source | Available operations |
|---|---|
| DOCX | Text and simple HTML. PDF and ODT with LibreOffice. Markdown and LaTeX with Pandoc |
| PDF | Selectable text, page images, split, merge, and editable Word reconstruction |
| CSV and TSV | Delimited text, XLSX, and paginated PDF |
| XLSX | PDF and one CSV or TSV per worksheet |
| JPG, PNG, HEIC | Image format conversion when the encoder probe passes, PDF, compression, 500 KB target, and 1600 px resize |
| JPG and PNG | Embedded image in Word |
| Markdown | HTML, DOCX, and LaTeX with Pandoc. PDF with Pandoc and Tectonic |
| LaTeX | Cached offline PDF compilation with Tectonic. DOCX and Markdown with Pandoc |

Mixed selections show shared formats and actions. PDF merge follows the order supplied by Finder. PDF page exports, split PDFs, worksheet exports, and technical document bundles use output folders. Existing files and folders are preserved.

PDF-to-Word reconstructs text and simple aligned tables. Exact layout, columns, and embedded illustrations can change or be omitted. Vision recognizes image-only pages and flags low-confidence text. Native Word HTML preserves paragraphs and text. For formatted Word export, install LibreOffice. XLSX export uses stored formula results and underlying values, so dates and numbers can differ from formatted Excel display. CSV-to-XLSX stores values as text.

## Optional local engines

Install engines separately, then relaunch OpenLorikeet. The app searches the standard LibreOffice application path and common package-manager binary paths. Engine status is available from the menu bar.

- [LibreOffice](https://www.libreoffice.org/download/download-libreoffice/) for formatted Word PDF and ODT.
- [Pandoc](https://pandoc.org/installing.html) for Markdown and LaTeX conversion. A build with embedded data files supports sandboxed DOCX writing. Relative PNG and JPG assets inside the source folder are supported by the adapter. [Pandoc sandbox documentation](https://pandoc.org/MANUAL.html#option--sandbox)
- [Tectonic](https://tectonic-typesetting.github.io/) for PDF compilation. Populate the package cache for your projects separately. OpenLorikeet uses cached files only and disables shell escape. [Tectonic compile options](https://tectonic-typesetting.github.io/book/latest/v2cli/compile.html)

## Verify a build

```sh
./scripts/test.sh
./dist/OpenLorikeet.app/Contents/MacOS/OpenLorikeet --smoke-test
```

The smoke test needs a logged-in graphical macOS session. See the [Finder checklist](docs/GESTURE_TESTING.md) and [verification status](BUILD_STATUS.md). Signing and distribution instructions are in [PACKAGING.md](docs/PACKAGING.md).
