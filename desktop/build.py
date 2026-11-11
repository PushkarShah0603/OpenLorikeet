"""Run on the target OS: python desktop/build.py."""
from pathlib import Path
import shutil
import importlib.metadata
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
subprocess.run([sys.executable, '-m', 'PyInstaller', '--noconfirm', '--clean', '--windowed',
    '--name', 'OpenLorikeet', '--paths', str(root/'desktop'),
    '--add-data', str(root/'docs/assets') + ':docs/assets',
    '--distpath', str(root/'dist/portable'), '--workpath', str(root/'.build/portable'),
    '--specpath', str(root/'.build'), str(root/'desktop/main.py')], check=True, cwd=root)
bundle = root/'dist/portable/OpenLorikeet'
notices = bundle/'licenses'
notices.mkdir(exist_ok=True)
shutil.copy(root/'desktop/THIRD_PARTY.md', notices)
for distribution in importlib.metadata.distributions():
    for entry in distribution.files or []:
        if any(word in str(entry).lower() for word in ('license', 'copying', 'copyright')):
            source = Path(distribution.locate_file(entry))
            if source.is_file():
                target = notices/distribution.metadata['Name']/Path(*[part for part in entry.parts if part not in ('..', '.', '/')])
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(source, target)
name = 'OpenLorikeet-'  + ('Windows-x64' if sys.platform=='win32' else 'Linux-x64' if sys.platform.startswith('linux') else 'macOS-portable')
archive_format = 'gztar' if sys.platform.startswith('linux') else 'zip'
archive = shutil.make_archive(str(root/'dist'/name), archive_format, root/'dist/portable', 'OpenLorikeet')
print('Packaged', archive)
