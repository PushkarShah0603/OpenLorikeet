from pathlib import Path
import sys
import tempfile
import unittest
import importlib.util
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lorikeet.core import actions, convert, page_order, publish

class CoreTests(unittest.TestCase):
    def test_order_and_routes(self):
        self.assertEqual(page_order('3, 2-1',3), [2,1,0])
        for value in ('1,1','0','4','1-2-3',''):
            with self.assertRaises(ValueError): page_order(value,3)
        self.assertEqual(actions(['unknown.bin']), [])
        self.assertFalse(actions(['a.pdf','b.docx'],True))
        with patch('lorikeet.core.office', return_value=None):
            self.assertNotIn('pdf',[a.key for a in actions(['a.docx'])])
    def test_exclusive_publication(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp); source=p/'source'; source.write_text('new')
            dest=p/'output.txt'; dest.write_text('original')
            result=publish(source,dest)
            self.assertEqual(dest.read_text(),'original'); self.assertEqual(result.read_text(),'new')
    @unittest.skipUnless(importlib.util.find_spec("docx"), "python-docx is not installed")
    def test_word_pictures(self):
        from docx import Document
        from PIL import Image
        from lorikeet.core import office
        if not office(): self.skipTest('LibreOffice unavailable')
        from pypdf import PdfReader
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp); Image.new('RGB',(64,64),'red').save(p/'photo.png')
            doc=Document(); doc.add_paragraph('Image fixture'); doc.add_picture(str(p/'photo.png')); doc.save(p/'manual.docx')
            result=convert([p/'manual.docx'],'pdf')[0]
            reader=PdfReader(result)
            self.assertTrue(any(len(page.images) for page in reader.pages))
    def test_images_and_pdf_tools(self):
        from PIL import Image
        from pypdf import PdfReader
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp); Image.new('RGB',(60,40),'blue').save(p/'photo.png')
            pdf=convert([p/'photo.png'],'pdf')[0]
            self.assertEqual(len(PdfReader(pdf).pages),1)
            merged=convert([pdf,pdf],'pdf-merge')[0]
            self.assertEqual(len(PdfReader(merged).pages),2)
            ordered=convert([merged],'pdf-organize',{'pages':'2'})[0]
            self.assertEqual(len(PdfReader(ordered).pages),1)
            tagged=convert([pdf],'pdf-metadata',{'title':'A bird'})[0]
            self.assertEqual(PdfReader(tagged).metadata.title,'A bird')
            self.assertEqual(len(convert([merged],'pdf-split')),2)
    @unittest.skipUnless(importlib.util.find_spec("openpyxl"), "openpyxl is not installed")
    def test_csv_literal_values(self):
        from openpyxl import load_workbook
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'table.csv'; p.write_text('id,value\n001,=1+2\n')
            xlsx=convert([p],'xlsx')[0]
            book=load_workbook(xlsx); sheet=book.active
            self.assertEqual(sheet['A2'].value,'001'); self.assertEqual(sheet['B2'].data_type,'s')
            book.close()


class ReviewRegressionTests(unittest.TestCase):
    def test_transparent_image_pdf_has_white_background(self):
        from PIL import Image
        from pypdf import PdfReader
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp)/'transparent.png'
            Image.new('RGBA', (40,40), (0,0,0,0)).save(source)
            output = convert([source], 'pdf')[0]
            pixel = PdfReader(output).pages[0].images[0].image.convert('RGB').getpixel((0,0))
            self.assertTrue(all(value > 245 for value in pixel), pixel)

    @unittest.skipUnless(importlib.util.find_spec('docx'), 'python-docx is not installed')
    def test_word_table_text_survives_plain_exports(self):
        from docx import Document
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp)/'table.docx'
            doc = Document(); doc.add_paragraph('Before')
            table = doc.add_table(rows=1, cols=1); table.cell(0,0).text = 'TABLE CONTENT'
            doc.add_paragraph('After'); doc.save(source)
            for target in ('txt', 'html'):
                text = convert([source], target)[0].read_text(encoding='utf-8')
                self.assertLess(text.index('Before'), text.index('TABLE CONTENT'))
                self.assertLess(text.index('TABLE CONTENT'), text.index('After'))

    def test_csv_quotes_and_limits(self):
        with tempfile.TemporaryDirectory() as tmp:
            source=Path(tmp)/'table.csv'
            source.write_text('id,value\n001,"line 1\nline 2"\n', encoding='utf-8')
            result=convert([source], 'tsv')[0].read_text(encoding='utf-8')
            self.assertIn('001',result); self.assertIn('line 2',result)
            source.write_text('"unclosed', encoding='utf-8')
            with self.assertRaises(Exception): convert([source], 'tsv')
            source.write_text('x'*32768, encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'limits'): convert([source], 'tsv')

    def test_long_unicode_output_name(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp); source=root/'source'; source.write_text('copy')
            result=publish(source, root/('é'*125+' converted.pdf'))
            self.assertLessEqual(len(result.name.encode('utf-8')),255)
            self.assertEqual(result.read_text(),'copy')

    def test_cmyk_jpeg_converts_to_png(self):
        from PIL import Image
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp)/'print.jpg'
            Image.new('CMYK', (40,40), (0,255,255,0)).save(source)
            output = convert([source], 'png')[0]
            with Image.open(output) as image:
                self.assertEqual(image.size, (40,40))
                self.assertEqual(image.format, 'PNG')

if __name__=='__main__': unittest.main()
