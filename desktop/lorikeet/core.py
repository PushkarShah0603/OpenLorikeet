"""Local conversions. Every job stages, validates, and exclusively publishes its copy."""
from pathlib import Path
import csv
import os
import shutil
import subprocess
import tempfile
from dataclasses import dataclass


@dataclass(frozen=True)
class Action:
    key: str
    label: str


def office():
    candidates = [shutil.which('libreoffice'), shutil.which('soffice'),
                  '/Applications/LibreOffice.app/Contents/MacOS/soffice']
    for root in (os.environ.get('PROGRAMFILES', ''), os.environ.get('PROGRAMFILES(X86)', '')):
        if root:
            candidates.append(str(Path(root) / 'LibreOffice/program/soffice.exe'))
    return next((str(p) for p in candidates if p and Path(p).is_file()), None)


def actions(paths, tools=False):
    def single(path):
        ext = Path(path).suffix.lower()
        keys = []
        if ext == '.pdf':
            keys = [('pdf-compress', 'Compress'), ('pdf-metadata', 'Metadata'),
                    ('pdf-organize', 'Organize'), ('pdf-split', 'Split pages')] if tools else [('txt', 'TXT')]
        elif ext in ('.png', '.jpg', '.jpeg', '.webp', '.bmp', '.tiff'):
            keys = [(x, x.upper()) for x in ('png', 'jpg', 'pdf', 'docx') if '.' + x != ext]
            keys += [('image-compress', 'Compress'), ('image-resize', 'Resize')]
        elif ext == '.docx':
            keys = [('txt', 'TXT'), ('html', 'HTML')]
            if office(): keys = [('pdf', 'PDF'), ('odt', 'ODT')] + keys
        elif ext in ('.csv', '.tsv', '.xlsx'):
            keys = [(x, x.upper()) for x in ('csv', 'tsv', 'xlsx', 'pdf') if '.' + x != ext]
        elif ext in ('.md', '.markdown', '.tex') and shutil.which('pandoc'):
            keys = [(x, x.upper()) for x in ('html', 'docx', 'md') if '.' + x != ext]
            if office() and ext != '.tex': keys += [('pdf', 'PDF')]
        return dict(keys)
    if not paths: return []
    available = single(paths[0])
    for path in paths[1:]:
        other = single(path)
        available = {k: v for k, v in available.items() if k in other}
    if tools and len(paths) > 1 and all(Path(p).suffix.lower() == '.pdf' for p in paths):
        available = {'pdf-merge': 'Merge', **available}
    return [Action(k, v) for k, v in available.items()]


def page_order(value, count):
    result = []
    for part in value.split(','):
        ends = part.strip().split('-')
        if len(ends) == 1: values = [int(ends[0])]
        elif len(ends) == 2:
            a, b = map(int, ends)
            values = range(a, b + (1 if b >= a else -1), 1 if b >= a else -1)
        else: raise ValueError('Use page numbers and ranges, for example 3, 1-2.')
        for number in values:
            if number < 1 or number > count or number - 1 in result:
                raise ValueError('Pages must be within the document and cannot repeat.')
            result.append(number - 1)
    if not result: raise ValueError('Choose at least one page.')
    return result


def publish(source, desired):
    """Exclusive file creation avoids overwriting even with competing processes."""
    desired = Path(desired)
    for index in range(10000):
        suffix = '' if index == 0 else f' ({index})'
        stem = desired.stem
        while len((stem + suffix + desired.suffix).encode('utf-8')) > 255:
            stem = stem[:-1]
        target = desired.with_name(stem + suffix + desired.suffix)
        try:
            with target.open('xb') as out:
                try:
                    with Path(source).open('rb') as incoming: shutil.copyfileobj(incoming, out)
                except BaseException:
                    target.unlink(missing_ok=True)
                    raise
            return target
        except FileExistsError: continue
    raise ValueError('Too many files share this output name.')


def run(args, cwd=None):
    try:
        done = subprocess.run(args, cwd=cwd, capture_output=True, timeout=180,
                              creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
    except subprocess.TimeoutExpired as exc: raise ValueError('Conversion exceeded three minutes.') from exc
    if done.returncode: raise ValueError(done.stderr.decode(errors='replace')[-1000:] or 'Conversion engine failed.')


def office_convert(source, target, directory):
    engine = office()
    if not engine: raise ValueError('Install LibreOffice to preserve Word pictures and layout in PDF.')
    profile = directory / 'office-profile'
    run([engine, '-env:UserInstallation=' + profile.as_uri(), '--headless', '--convert-to', target,
         '--outdir', str(directory), str(source)])
    output = directory / (source.stem + '.' + target)
    if not output.is_file(): raise ValueError('LibreOffice did not create the requested output.')
    return output


def text_pdf(text, output):
    from reportlab.pdfgen import canvas
    import textwrap
    c = canvas.Canvas(str(output))
    y = 800
    for line in text.splitlines():
        for wrapped in textwrap.wrap(line, 95, replace_whitespace=False) or ['']:
            if y < 45: c.showPage(); y = 800
            c.drawString(40, y, wrapped); y -= 14
    c.save()


def validate(path):
    if not path.is_file() or path.stat().st_size == 0: raise ValueError('The engine produced an empty output.')
    if path.suffix == '.pdf':
        from pypdf import PdfReader
        if not PdfReader(path).pages: raise ValueError('The PDF has no pages.')
    elif path.suffix in ('.png', '.jpg'):
        from PIL import Image
        with Image.open(path) as image: image.verify()
    elif path.suffix == '.docx':
        from docx import Document
        Document(path)
    elif path.suffix == '.xlsx':
        from openpyxl import load_workbook
        book = load_workbook(path, read_only=True); book.close()


def convert(paths, action, options=None):
    options = options or {}
    paths = [Path(p).resolve(strict=True) for p in paths]
    if not paths or any(not p.is_file() for p in paths): raise ValueError('Select local files.')
    if any(p.stat().st_size > 128 * 1024 * 1024 for p in paths): raise ValueError('Choose files smaller than 128 MB.')
    if action not in {a.key for a in actions(paths, action.startswith('pdf-'))}:
        raise ValueError('This action is unavailable for the selected files or installed engines.')
    with tempfile.TemporaryDirectory(prefix='openlorikeet-') as temporary:
        root = Path(temporary)
        products = []
        for index, source in enumerate(paths):
            if action == 'pdf-merge' and index > 0: break
            work = root / str(index); work.mkdir()
            ext = source.suffix.lower()
            out_ext = 'pdf' if action.startswith('pdf-') else ('jpg' if action == 'image-compress' else 'png' if action == 'image-resize' else action)
            output = work / (source.stem + '.' + out_ext)
            suffix = ' converted'
            if ext == '.pdf':
                from pypdf import PdfReader, PdfWriter
                reader = PdfReader(source)
                if reader.is_encrypted: raise ValueError('Unlock the PDF before converting it.')
                if len(reader.pages) > 500: raise ValueError('Choose a PDF with at most 500 pages.')
                if action == 'txt': output.write_text('\n\n'.join(p.extract_text() or '' for p in reader.pages), encoding='utf-8')
                elif action == 'pdf-split':
                    for number, page in enumerate(reader.pages, 1):
                        writer = PdfWriter(); writer.add_page(page)
                        part = work / f'{source.stem} page {number}.pdf'; writer.write(part)
                        products.append((part, source.parent / part.name))
                    continue
                else:
                    writer = PdfWriter()
                    if action == 'pdf-merge':
                        for path in paths:
                            merged = PdfReader(path)
                            if merged.is_encrypted: raise ValueError('Unlock every PDF before merging.')
                            if len(writer.pages) + len(merged.pages) > 500: raise ValueError('Merge supports at most 500 pages.')
                            for page in merged.pages: writer.add_page(page)
                        suffix = ' merged'
                    else:
                        order = page_order(options.get('pages', ''), len(reader.pages)) if action == 'pdf-organize' else range(len(reader.pages))
                        for number in order: writer.add_page(reader.pages[number])
                        if reader.metadata:
                            writer.add_metadata({k: str(v) for k, v in reader.metadata.items() if v is not None})
                        if action == 'pdf-metadata':
                            writer.add_metadata({'/' + k.title(): str(options.get(k, '')) for k in ('title', 'author', 'subject', 'keywords')})
                        if action == 'pdf-compress':
                            for page in writer.pages: page.compress_content_streams()
                            suffix = ' compressed'
                    writer.write(output)
                    if action == 'pdf-compress' and output.stat().st_size >= source.stat().st_size:
                        raise ValueError('This PDF is already compact. No smaller copy was saved.')
            elif ext in ('.png', '.jpg', '.jpeg', '.webp', '.bmp', '.tiff'):
                from PIL import Image, ImageOps
                with Image.open(source) as raw:
                    if raw.width * raw.height > 64000000 or getattr(raw, 'n_frames', 1) != 1:
                        raise ValueError('Choose a single image with at most 64 million pixels.')
                    image = ImageOps.exif_transpose(raw)
                    if action == 'docx':
                        from docx import Document
                        from docx.shared import Inches
                        png = work / 'picture.png'; image.convert('RGBA').save(png)
                        doc = Document(); doc.add_picture(str(png), width=Inches(6)); doc.save(output)
                    elif action == 'pdf':
                        rgba = image.convert('RGBA')
                        white = Image.new('RGB', image.size, 'white')
                        white.paste(rgba, mask=rgba.getchannel('A'))
                        white.save(output, 'PDF', resolution=150)
                    else:
                        if action == 'image-resize': image.thumbnail((1600, 1600)); suffix = ' resized'
                        if out_ext == 'jpg':
                            rgba = image.convert('RGBA'); white = Image.new('RGB', image.size, 'white'); white.paste(rgba, mask=rgba.getchannel('A')); image = white
                        if out_ext == 'png' and image.mode not in ('1', 'L', 'LA', 'P', 'RGB', 'RGBA', 'I', 'I;16'):
                            image = image.convert('RGBA')
                        image.save(output, quality=82, optimize=True)
                        if action == 'image-compress':
                            suffix = ' compressed'
                            if output.stat().st_size >= source.stat().st_size: raise ValueError('No smaller image could be created.')
            elif ext == '.docx':
                if action in ('pdf', 'odt'): output = office_convert(source, action, work)
                else:
                    from docx import Document
                    doc = Document(source)
                    from docx.table import Table
                    blocks = list(doc.iter_inner_content())
                    text = '\n'.join('\n'.join('\t'.join(cell.text for cell in row.cells) for row in block.rows) if isinstance(block, Table) else block.text for block in blocks)
                    if action == 'html':
                        import html
                        body = []
                        for block in blocks:
                            if isinstance(block, Table):
                                body.append('<table>' + ''.join('<tr>' + ''.join('<td>' + html.escape(cell.text) + '</td>' for cell in row.cells) + '</tr>' for row in block.rows) + '</table>')
                            else: body.append('<p>' + html.escape(block.text) + '</p>')
                        text = '<!doctype html><meta charset="utf-8"><title>Document</title>' + ''.join(body)
                    output.write_text(text, encoding='utf-8')
            elif ext in ('.csv', '.tsv', '.xlsx'):
                if action == 'xlsx' or ext == '.xlsx':
                    from openpyxl import Workbook, load_workbook
                cell_budget = 1000000
                def bounded_rows(rows):
                    nonlocal cell_budget
                    result = []
                    for row in rows:
                        cell_budget -= len(row)
                        if len(result) >= 100000 or len(row) > 1024 or cell_budget < 0 or any(len(str(v or '')) > 32767 for v in row):
                            raise ValueError('The table exceeds supported row, column, or cell limits.')
                        result.append(row)
                    return result
                if ext == '.xlsx':
                    book = load_workbook(source, read_only=True, data_only=True)
                    try:
                        if len(book.worksheets) > 100 or any((sheet.max_row or 0) > 100000 or (sheet.max_column or 0) > 1024 for sheet in book.worksheets):
                            raise ValueError('The workbook exceeds supported sheet dimensions.')
                        sheets = [(sheet.title, bounded_rows(sheet.values)) for sheet in book.worksheets]
                    finally: book.close()
                else:
                    with source.open(encoding='utf-8-sig', newline='') as stream:
                        sheets = [(source.stem, bounded_rows(csv.reader(stream, delimiter='\t' if ext == '.tsv' else ',', strict=True)))]
                if action == 'xlsx':
                    book = Workbook(); sheet = book.active
                    for row in sheets[0][1]:
                        sheet.append(row)
                        for cell in sheet[sheet.max_row]: cell.data_type = 's'
                    book.save(output)
                elif action == 'pdf':
                    from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph, PageBreak
                    from reportlab.lib.styles import getSampleStyleSheet
                    from reportlab.lib.pagesizes import landscape, A4
                    from xml.sax.saxutils import escape
                    flow = []; styles = getSampleStyleSheet()
                    for name, rows in sheets:
                        if flow: flow.append(PageBreak())
                        flow.append(Paragraph(escape(name), styles['Heading1']))
                        width = max((len(r) for r in rows), default=1)
                        # Wide sheets are split into groups rather than shrinking text indefinitely.
                        for start in range(0, width, 6):
                            if start: flow.append(PageBreak())
                            count = min(6, width - start)
                            data = [[Paragraph(escape(str('' if v is None else v)), styles['BodyText']) for v in list(row[start:start+count]) + [''] * max(0, count-len(row[start:start+count]))] for row in rows]
                            if data:
                                table = Table(data, colWidths=[740/count]*count, repeatRows=1)
                                table.setStyle(TableStyle([('VALIGN',(0,0),(-1,-1),'TOP'),('BACKGROUND',(0,0),(-1,0),'#e4eddf')]))
                                flow.append(table)
                    if not flow: raise ValueError('The spreadsheet is empty.')
                    SimpleDocTemplate(str(output), pagesize=landscape(A4), leftMargin=40, rightMargin=40).build(flow)
                else:
                    for number, (name, rows) in enumerate(sheets, 1):
                        part = work / f'{source.stem} sheet {number}.{action}'
                        with part.open('w', encoding='utf-8', newline='') as stream:
                            csv.writer(stream, delimiter='\t' if action == 'tsv' else ',').writerows(rows)
                        products.append((part, source.parent / part.name))
                    continue
            else:
                if action == 'pdf':
                    docx = work / (source.stem + '.docx')
                    run(['pandoc', '--sandbox', str(source), '-o', str(docx)], cwd=source.parent)
                    output = office_convert(docx, 'pdf', work)
                else: run(['pandoc', '--sandbox', str(source), '-o', str(output)], cwd=source.parent)
            products.append((output, source.with_name(source.stem + suffix + '.' + out_ext)))
        for product, _ in products: validate(product)
        saved = []
        try:
            for product, desired in products: saved.append(publish(product, desired))
        except BaseException:
            for path in saved: path.unlink(missing_ok=True)
            raise
        return saved
