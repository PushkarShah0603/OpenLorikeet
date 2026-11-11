# Third-party components

Portable packages depend on Qt for Python / PySide6 and Shiboken (LGPLv3/GPLv3 or commercial), Pillow (HPND), pypdf (BSD-3-Clause), python-docx (MIT), openpyxl (MIT), ReportLab (BSD), and the Python runtime (PSF license). PyInstaller uses GPL with its bootloader exception. Consult the exact license files included with your installed versions before distribution.

Qt libraries are dynamically packaged and must remain replaceable under the LGPL distribution option. Include the actual license texts, copyright notices, and source-access information in distributed packages. Build source and dependency list are available in this repository; Qt source is available at https://code.qt.io/ and https://www.qt.io/development/qt-framework/qt-licensing. Package licensing notices are collected from installed distributions by `build.py`.

LibreOffice and Pandoc are separately installed tools and are not included in the portable ZIPs. Character artwork provenance is documented in `Sources/OpenLorikeetApp/Assets/README.md`.
