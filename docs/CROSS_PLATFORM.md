# OpenLorikeet on three desktops

All editions are local background utilities with a radial format picker, the same cartoon lorikeet, and converted copies saved beside the source. Existing files are never silently replaced. macOS uses Swift/AppKit; Windows and Linux use the Qt implementation in `desktop/`. The portable implementation also runs from source on macOS for development.

**Status:** the native Mac package is locally built. Windows/Linux source and CI workflows are ready for their first native build; executables and real desktop gestures are not yet verified. Do not describe those editions as production releases before the acceptance checks below pass.

## Shared experience and coverage

| Area | macOS native | Windows / Linux portable |
|---|---|---|
| Background app, wheel, animated bird | Menu bar | System tray |
| Gesture | Finder Shift-drag | Shift-drag on Windows and Linux X11; tray-opened wheel on Wayland |
| File picker | Convert Files… | Convert files… |
| PDF tools entry | Command-drag or menu | PDF tools… in tray |
| Word → PDF with pictures | Built-in renderer or LibreOffice | Requires LibreOffice |
| Pictures | JPG/PNG, conditional HEIC | JPG/PNG/WebP/BMP/TIFF input, JPG/PNG output |
| Picture → PDF / Word | Yes | Yes |
| PDF merge, split, order, metadata, text | Yes | Yes |
| PDF compression | Image optimization | Lossless content-stream compression; savings vary |
| PDF → editable Word / page pictures | Native reconstruction | Not implemented |
| CSV/TSV/XLSX and table PDF | Yes | Yes; PDF groups wide tables into six-column sections |
| Markdown routes | Pandoc | Pandoc; PDF also needs LibreOffice |
| TeX PDF / Vision OCR | Tectonic / Vision (verification pending) | Not implemented |
| Reduced motion | System setting | Tray preference |
| Launch at login | Menu option | Configure in OS startup settings |

Routes requiring unavailable engines stay hidden. The portable worker limits each file to 128 MB, PDF operations to 500 pages, and external jobs to three minutes. Text/HTML document exports are simple content exports. ReportLab table PDFs currently use its standard fonts; complex scripts need further font support and testing.

## Run from source

Use Python 3.12 on Windows or Linux. Install [LibreOffice](https://www.libreoffice.org/download/download-libreoffice/) for Word PDF export. Pandoc is optional. Close and relaunch after installing engines.

Windows PowerShell, from the repository root:

```powershell
py -3.12 -m venv .venv
.venv\Scripts\python -m pip install -r desktop/requirements.txt
.venv\Scripts\python desktop/main.py
```

Linux, from the repository root:

```sh
python3 -m venv .venv
. .venv/bin/activate
pip install -r desktop/requirements.txt
python desktop/main.py
```

Qt needs desktop graphics libraries. On Ubuntu 22.04 or newer:

```sh
sudo apt install libegl1 libopengl0 libxcb-cursor0 libxkbcommon-x11-0 libreoffice-writer
```

GNOME may need a StatusNotifier/AppIndicator extension to show tray icons. If the tray is unavailable, the drop wheel opens at startup. On Wayland, open the wheel from the tray **before** dragging files onto it. Windows and X11 monitor only Shift plus left-button state; actual file paths are received through the OS drop. Ordinary Shift-click may also reveal the empty wheel; Escape dismisses it.

## Build packages

Run on each target OS with the environment above:

```sh
python desktop/build.py
```

Windows produces `dist/OpenLorikeet-Windows-x64.zip`. Extract the **whole folder**, then run `OpenLorikeet.exe`. Linux produces `dist/OpenLorikeet-Linux-x64.tar.gz`; extract the archive (preserving executable permissions) and run `./OpenLorikeet/OpenLorikeet`. Libraries and assets alongside the executable are required. LibreOffice and Pandoc are separate installations. Packages include third-party notices. These are portable ZIPs; installers, Windows signing, and Linux package-manager integration remain release work.

Mac continues to use `./scripts/package.sh` and produces its native app ZIP.

## Your next steps

1. Push the committed changes to `main`.
2. In GitHub, open **Actions → Build desktop apps → Run workflow**. It also runs on pushes and pull requests.
3. Wait for Windows, Linux, macOS, and website jobs to pass. Download each OS artifact from the run summary. Artifacts require GitHub sign-in and eventually expire; they are testing packages, not permanent public downloads.
4. Test Windows on Windows 10/11 x64 and Linux on a supported desktop. Start with the tray file picker, then test Shift-drag, PDF tools, multiple files, failed input, existing output names, Reduce motion, and dismiss/quit. Test X11 and Wayland separately.
5. Convert a Word document containing photos to PDF with LibreOffice installed. Confirm every photo and table visually. Open image, spreadsheet, metadata, reordered, merged, and split outputs in their normal applications. Verify originals and existing files survive.
6. After all native builds and website checks pass on main, the workflow publishes a development prerelease containing the Windows ZIP, Linux tar.gz, Mac ZIP, and SHA256SUMS.txt. The website resolves direct downloads from the newest complete release. Use **OpenLorikeet** as the product name. Sign/notarize public Mac builds and sign Windows binaries when distribution credentials are available.
7. For the website, choose **Settings → Pages → Deploy from a branch → main → /docs**. The redesigned site will publish at `https://pushkarshah0603.github.io/OpenLorikeet/` after your push. Download buttons resolve actual uploaded release assets. If no complete release is available, the site explains that packages are not published yet and links to the release list.

## Verification commands

```sh
python -m unittest discover -s desktop/tests -v
QT_QPA_PLATFORM=offscreen python desktop/check_ui.py
node scripts/check-site.mjs
```

On PowerShell, set `$env:QT_QPA_PLATFORM = 'offscreen'` before the UI check. The UI check validates resources and rendering, not real drag delivery.

[Qt system tray support](https://doc.qt.io/qtforpython-6/PySide6/QtWidgets/QSystemTrayIcon.html) · [PyInstaller target-platform builds](https://pyinstaller.org/en/stable/usage.html#supporting-multiple-operating-systems)

## Download repair

The initial Windows/Linux jobs succeeded, but their buttons led to Actions instead of downloads and no public release existed. The Mac CI compiler also timed out while inferring a Word picture cell-width expression, preventing its package. The expression now uses explicit intermediate types. Native packaged self-tests check portable imports and mascot resources before artifacts are uploaded. Once all jobs pass, the release job uploads a complete development download set and checksums. Ordinary source pushes and manual main-branch builds trigger this; pull requests cannot publish. Real desktop testing remains separate.
