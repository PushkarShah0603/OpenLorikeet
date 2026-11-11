# Final engineering review

Review date: 11 November 2026. Verdict: suitable for development testing after the review changes pass native CI. Not yet a fully verified, signed public stable release. No critical overwrite defect was found in the reviewed publication paths; this is a bounded review, not a guarantee that all inputs or desktops work.

## Scope

Reviewed the native Swift conversion core and tray/menu interactions, portable Python conversion workers and Qt interactions, mascot lifecycle, installer definitions, package/resource paths, CI permissions and release gates, website presentation and download selection, source instructions, and regression fixtures. No private manuals, photo references, credentials, or build products are included in the commit.

## Issues corrected during this review

| Finding | Repair | Verification |
|---|---|---|
| Portable transparent PNG-to-PDF discarded alpha onto black | Composite onto white before PDF encoding | Regression reproduced black output before repair; decoded PDF image is white after repair |
| Portable Word TXT/HTML omitted table text | Read paragraphs and tables in document order; HTML includes escaped table cells | Regression added; local execution pending python-docx, included in native CI |
| CMYK JPEG input could fail PNG export | Normalize unsupported PNG modes; normalize images embedded in DOCX | CMYK JPEG-to-PNG regression passes locally |
| Long source names could exceed filename limits after adding output suffixes | Trim Unicode stems while retaining collision suffix and extension | Long multibyte-name and exclusive-publication checks pass |
| Portable spreadsheets lacked consistent limits; malformed CSV quotes could be accepted | Bound rows, columns, cells and field sizes; strict CSV parsing; cap XLSX dimensions and sheets | CSV quotes, multiline content, size-limit and existing identifier checks |
| Multiple portable requests could show a success while another batch was running | Reject overlapping batch starts with a readable message | Source review; Qt runtime acceptance pending for this change |
| Portable picker required mouse selection | Arrow keys select an action, Enter submits, Escape dismisses | Qt UI regression added; awaits native CI |
| Linux installed-app checks only used the offscreen plugin | Declare additional X11 runtime dependencies and test packaged app with xcb under Xvfb | New CI check; requires next pushed run |
| Website showed Python/Swift build commands to ordinary download users | Show plain installation steps, name Apple silicon support, distinguish portable archives from installers | Site behavior checks pass for both archive and installer releases |
| CI jobs could run without an explicit short upper bound | Set build/test and publishing job timeouts | Workflow review |

Portable single-image inputs are now limited to 64 million pixels; multi-frame inputs fail explicitly instead of silently exporting only the first frame.

## Local verification

- `./scripts/test.sh`: available native regression groups pass. LibreOffice and Pandoc integration skip because tools are absent. Vision OCR pixel-buffer allocation remains unverified in this environment.
- `./scripts/package.sh`: release build, app metadata, ad-hoc signature and ZIP integrity pass. Fresh extraction has a valid strict signature and the mascot atlas.
- `python3 -m unittest discover -s desktop/tests -v`: 10 tests, 7 pass and 3 skip locally (python-docx/openpyxl missing). New dependency-backed tests must pass in CI before shipping these changes.
- `node scripts/check-site.mjs`: links/assets, picker demo/reset, Reduced Motion timing, platform switching, actual release-asset links, incomplete/draft/offline fallbacks, installer preference and installation instructions pass.
- Python compilation, shell syntax, JavaScript syntax, and `git diff --check` pass.
- Qt runtime and live browser visual checks could not be completed locally; the installed environment lacks PySide6 and browser access. Static/behavior checks do not establish mobile visual quality or real OS drag behavior.

## Actual GitHub status checked during review

[Portable release build 43009000936](https://github.com/PushkarShah0603/OpenLorikeet/actions/runs/43009000936) passed all platform jobs and published [the existing three-platform development release](https://github.com/PushkarShah0603/OpenLorikeet/releases/tag/desktop-43009000936-1).

[Installer build 43009933865](https://github.com/PushkarShah0603/OpenLorikeet/actions/runs/43009933865), for commit fceef90, has passed Windows and Linux jobs, including setup/package creation, installed-app self-test, and uninstall. Website checks passed. The macOS job was still queued at the last check, so its combined installer release was not yet published. GitHub Pages deployment of fceef90 passed.

The fixes in this review are local until pushed and have not been exercised by either of those remote runs. The website continues to resolve the latest complete published release while a newer build is incomplete.

## Remaining release conditions

1. **Native CI for the review commit:** push it, then require all checks and the combined release job to pass. A queued job is not a failure and has no package to publish yet.
2. **Real desktop acceptance:** test Windows Explorer drag, Finder drag, X11 and Wayland behavior, normal display rendering, keyboard navigation, tray visibility, repeated conversions, and opening saved outputs. Installed-app headless checks do not establish these behaviors.
3. **Public distribution signing:** Windows binaries are unsigned and Mac builds use ad-hoc signing. Developer ID/notarization and Windows code signing remain necessary for a smoother mainstream download experience.
4. **Feature parity:** all three share the same app type, wheel and character, but not every engine. Portable editions lack the native Mac PDF-to-Word/OCR, HEIC and cached TeX features. Portable conversion cancellation is not exposed; external commands have a three-minute timeout while built-in work relies on input limits. See CROSS_PLATFORM.md.
5. **Document fidelity:** inspect representative complex Word documents using LibreOffice on Windows/Linux, verify fonts, pictures and pagination, and check native Mac floating-picture reflow. PDF-to-Word is reconstruction. Portable table PDFs use standard fonts; complex scripts and unusually tall cells need further work.
6. **Broader Linux support:** .deb targets Debian/Ubuntu x64. GNOME may need a tray extension; Wayland uses a tray-opened wheel. Other distributions and ARM Linux are not certified.
7. **Dependency reproducibility:** requirements currently constrain version ranges rather than a fully locked dependency set. Native CI checks each resolved set; future dependency updates may still require fixes.

## Recommended next step

Push this review commit, let the native build/release pipeline finish, and have one user on each target desktop perform the manual checks above. Keep downloads labeled development builds until those checks and distribution signing are completed.
