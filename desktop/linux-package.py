"""Build an installable Debian/Ubuntu x64 package after build.py."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='lorikeet-deb-') as temporary:
    package = Path(temporary)
    destination = package/'opt/openlorikeet'
    shutil.copytree(root/'dist/portable/OpenLorikeet', destination)
    binary = destination/'OpenLorikeet'
    binary.chmod(binary.stat().st_mode | 0o111)
    control = package/'DEBIAN'; control.mkdir()
    (control/'control').write_text('''Package: openlorikeet
Version: 0.1.0
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Pushkar <shahpushkar0603@gmail.com>
Depends: libc6 (>= 2.35), libegl1, libopengl0, libxcb-cursor0, libxkbcommon-x11-0, libx11-6, libx11-xcb1, libxcb-icccm4, libxcb-keysyms1, libxcb-image0, libxcb-render-util0
Recommends: libreoffice-writer
Homepage: https://github.com/PushkarShah0603/OpenLorikeet
Description: Local file converter with an animated desktop companion
 Tray utility with a radial picker for documents, images and PDF tools.
''')
    applications = package/'usr/share/applications'; applications.mkdir(parents=True)
    (applications/'openlorikeet.desktop').write_text('''[Desktop Entry]
Type=Application
Name=OpenLorikeet
Comment=Convert local documents, pictures and PDFs
Exec=/opt/openlorikeet/OpenLorikeet
Icon=openlorikeet
Terminal=false
Categories=Utility;Office;
StartupNotify=false
''')
    icons = package/'usr/share/icons/hicolor/256x256/apps'; icons.mkdir(parents=True)
    from PIL import Image
    with Image.open(root/'docs/assets/lorikeet.png') as image:
        image.resize((256,256)).save(icons/'openlorikeet.png')
    subprocess.run(['dpkg-deb', '--root-owner-group', '--build', str(package), str(root/'dist/OpenLorikeet-Linux-x64.deb')], check=True)
