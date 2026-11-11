<div align="center">

<img src="docs/assets/lorikeet.png" alt="OpenLorikeet app icon" width="112">

# OpenLorikeet

**Convert files from Finder with Shift-drag.**

macOS 15+ · Native AppKit · Local conversion

[Format guide](#formats-and-actions) · [Build from source](#build-from-source) · [GitHub Releases](https://github.com/PushkarShah0603/OpenLorikeet/releases)

</div>

OpenLorikeet is a menu bar utility for converting documents, images, and spreadsheets. Start dragging a file in Finder, hold **Shift**, and drop it on an output format. The animated cartoon lorikeet follows the selection and celebrates once a validated copy is saved beside the original.

## How it works

1. Start a drag from Finder or the Desktop. Multi-file selections are supported.
2. Hold **Shift** to reveal the format wheel. It shows actions shared by the selected files and supported by the installed engines.
3. Drop onto a segment. Use **Open** or **Show in Finder** from the result panel.

Hold **Command** during a PDF drag for the PDF tools wheel. You can also choose **Convert Files…** from the menu bar, select files, and pick an output or tool.

A batch keeps separate results for each file. OpenLorikeet validates each output before saving it and chooses a new name if the destination already exists. The menu bar includes engine status, launch at login, and a feather celebration toggle. Animations respect Reduce Motion.

## Formats and actions

| Input | Actions |
|---|---|
| **DOCX** | Built-in PDF, TXT, and text-based HTML. LibreOffice improves Word layout fidelity and adds ODT. Pandoc adds Markdown and LaTeX |
| **PDF** | Compress, edit metadata, organize pages, merge, split, extract selectable TXT, export page images, and reconstruct editable DOCX |
| **CSV / TSV** | XLSX, paginated PDF, and delimited text conversion |
| **XLSX** | PDF, or separate CSV and TSV files for each worksheet |
| **JPG / PNG / HEIC** | Available image formats, PDF, compression, 500 KB target, and 1600 px resize |
| **JPG / PNG** | Word document with the image embedded |
| **Markdown** | HTML, DOCX, and LaTeX with Pandoc. PDF with Pandoc and Tectonic |
| **LaTeX** | Cached offline PDF compilation with Tectonic. Markdown and DOCX with Pandoc |

PDF merge uses the order delivered by Finder. Page, sheet, and document bundle exports create folders. CSV-to-XLSX stores values as strings, preserving leading zeros and long identifiers. XLSX-to-text exports stored formula results and underlying cell values.

The built-in DOCX renderer uses macOS Word import and text layout, with explicit handling for embedded pictures and their crops. Floating pictures are placed in the text flow, so pagination and complex layouts can differ from Word. OpenLorikeet prefers LibreOffice for PDF if it is installed.

PDF compression optimizes embedded images for screen viewing and saves a copy only when it is smaller. Metadata edits cover title, author, subject, and keywords. Organize accepts page lists and ranges such as `3, 1-2` and omits pages you leave out.

PDF-to-Word reconstructs text and simple aligned tables. Complex layouts and illustrations can change or be omitted. OCR uses macOS Vision for image-only pages. HEIC output appears only when the encoder passes a round-trip check.

## Build from source

Requirements are **macOS 15 or newer** and **Swift 6** from Xcode or Command Line Tools.

```sh
git clone https://github.com/PushkarShah0603/OpenLorikeet.git
cd OpenLorikeet
./scripts/package.sh
open dist/OpenLorikeet.app
```

The app and an architecture-specific ZIP are written to `dist/`. The default build uses an ad-hoc signature for local development. Extract the ZIP and move the app to Applications for regular use. For Developer ID signing and notarization, see [Packaging](docs/PACKAGING.md).

### Optional engines

Install the tools you need and relaunch OpenLorikeet. The app checks the standard application and package-manager locations.

| Engine | Enables |
|---|---|
| [LibreOffice](https://www.libreoffice.org/download/download-libreoffice/) | Higher-fidelity DOCX to PDF and ODT export |
| [Pandoc](https://pandoc.org/installing.html) | Markdown, Word, and LaTeX routes. Use a build with embedded data files for sandboxed DOCX writing |
| [Tectonic](https://tectonic-typesetting.github.io/) | TeX and Markdown PDF routes. Populate your project’s package cache first |

Tectonic runs with cached resources and shell escape disabled. The Pandoc adapter limits imported image assets to local PNG or JPG files inside the source folder. [Tectonic compile options](https://tectonic-typesetting.github.io/book/latest/v2cli/compile.html) · [Pandoc sandbox documentation](https://pandoc.org/MANUAL.html#option--sandbox)

## Development and verification

```sh
./scripts/test.sh
node scripts/check-site.mjs
./dist/OpenLorikeet.app/Contents/MacOS/OpenLorikeet --smoke-test
```

The core checks generate their own fixtures. The site checks use Node.js and verify local links and demo behavior. Run the app smoke test in a logged-in graphical macOS session. See [Build status](BUILD_STATUS.md) for verified routes and open checks, and the [Finder checklist](docs/GESTURE_TESTING.md) for manual testing.

- `Sources/ConversionCore` contains the engine registry, queue, converters, and format validation.
- `Sources/OpenLorikeetApp` contains Finder interaction, the format wheel, and the status panel.
- `Tests/CoreChecks` contains the conversion and gesture fixtures.
- `docs/` contains the GitHub Pages site and project guides.

## Publish the project website

The static site is in [`docs/index.html`](docs/index.html). Open that file locally for a preview. After pushing `main`, open the repository’s **Settings → Pages**. Select **Deploy from a branch**, choose **main** and **/docs**, and save. GitHub Pages will publish the site at [pushkarshah0603.github.io/OpenLorikeet](https://pushkarshah0603.github.io/OpenLorikeet/). [GitHub Pages publishing documentation](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)

The Shift-drag workflow was inspired by [Open Tangerine](https://github.com/sintaxerrorpvtltd/Open-Tangerine).
