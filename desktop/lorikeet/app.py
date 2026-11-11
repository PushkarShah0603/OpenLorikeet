from pathlib import Path
import math
import sys
import time
from PySide6.QtCore import Qt, QTimer, Signal, QObject, QRunnable, QThreadPool, QUrl, QRectF, QSettings
from PySide6.QtGui import QPainter, QColor, QPixmap, QIcon, QCursor, QDesktopServices, QAction
from PySide6.QtWidgets import (QApplication, QWidget, QSystemTrayIcon, QMenu, QFileDialog,
    QMessageBox, QInputDialog, QVBoxLayout, QLabel, QPushButton, QHBoxLayout)
from .core import actions, convert, office
from .gesture import monitor

ASSETS = Path(getattr(sys, '_MEIPASS', Path(__file__).resolve().parents[2])) / 'docs/assets'


class Bird(QWidget):
    def __init__(self):
        super().__init__(); self.setFixedSize(100, 100)
        self.atlas = QPixmap(str(ASSETS / 'lorikeet-atlas.png'))
        self.pose = 'ready'; self.began = time.monotonic(); self.look = False
        self.timer = QTimer(self); self.timer.timeout.connect(self.update)
    def showEvent(self, event): self.timer.start(33)
    def hideEvent(self, event): self.timer.stop()
    def paintEvent(self, event):
        t = time.monotonic() - self.began
        reduced = QSettings().value('reducedMotion', False, type=bool)
        frame = {'ready': 2 if self.look else 0, 'working': 3, 'failed': 7, 'happy': 6}[self.pose]
        if not reduced:
            if self.pose == 'ready' and t % 3.7 > 3.54: frame = 1
            if self.pose == 'happy' and t < 1.8: frame = [6,5,4,5,6,5,4,5,6][min(8, int(t/.14))]
        p = QPainter(self); p.setRenderHint(QPainter.SmoothPixmapTransform)
        hop = abs(math.sin(t * 10)) * max(0, 1-t/1.4)*8 if self.pose == 'happy' and not reduced else 0
        p.drawPixmap(QRectF(0, 5-hop, 96, 96), self.atlas, QRectF(frame%4*self.atlas.width()/4, frame//4*self.atlas.height()/2, self.atlas.width()/4, self.atlas.height()/2))
    def set_pose(self, pose): self.pose = pose; self.began = time.monotonic(); self.update()


class Signals(QObject):
    done = Signal(list, list)


class Job(QRunnable):
    def __init__(self, paths, action, options):
        super().__init__(); self.paths=paths; self.action=action; self.options=options; self.signals=Signals()
    def run(self):
        saved, errors = [], []
        groups = [self.paths] if self.action == 'pdf-merge' else [[p] for p in self.paths]
        for group in groups:
            try: saved.extend(str(p) for p in convert(group, self.action, self.options))
            except Exception as exc: errors.append(Path(group[0]).name + ': ' + str(exc))
        self.signals.done.emit(saved, errors)


class Feedback(QWidget):
    def __init__(self):
        super().__init__(None, Qt.Tool | Qt.WindowStaysOnTopHint)
        self.setWindowTitle('OpenLorikeet'); self.resize(430, 145)
        layout=QHBoxLayout(self); self.bird=Bird(); layout.addWidget(self.bird)
        body=QVBoxLayout(); layout.addLayout(body)
        self.label=QLabel(); self.label.setWordWrap(True); self.label.setTextFormat(Qt.PlainText); body.addWidget(self.label)
        buttons=QHBoxLayout(); body.addLayout(buttons)
        self.open=QPushButton('Open'); self.folder=QPushButton('Show folder'); self.close=QPushButton('Dismiss')
        for button in (self.open,self.folder,self.close): buttons.addWidget(button)
        self.close.clicked.connect(self.hide); self.open.clicked.connect(lambda: self.launch(False)); self.folder.clicked.connect(lambda: self.launch(True))
        self.paths=[]
    def launch(self, folder):
        if self.paths: QDesktopServices.openUrl(QUrl.fromLocalFile(str(Path(self.paths[0]).parent if folder else self.paths[0])))
    def show_status(self, message, pose, paths=None):
        self.paths=paths or []; self.label.setText(message); self.bird.set_pose(pose)
        self.open.setEnabled(bool(self.paths)); self.folder.setEnabled(bool(self.paths))
        self.show(); self.raise_()


class Wheel(QWidget):
    def __init__(self, owner):
        super().__init__(None, Qt.Tool | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint)
        self.owner=owner; self.setWindowTitle('OpenLorikeet'); self.resize(370, 370)
        self.setAttribute(Qt.WA_TranslucentBackground); self.setAcceptDrops(True); self.setMouseTracking(True)
        self.paths=[]; self.choices=[]; self.hover=-1; self.tools=False
        self.bird=Bird(); self.bird.setParent(self); self.bird.move(135, 116)
    def reveal(self, tools=False, paths=None):
        self.tools=tools; self.paths=paths or []; self.refresh()
        point=QCursor.pos(); screen=QApplication.screenAt(point) or QApplication.primaryScreen(); area=screen.availableGeometry()
        self.move(max(area.left(),min(point.x()-185,area.right()-370)),max(area.top(),min(point.y()-185,area.bottom()-370)))
        self.show(); self.raise_(); self.activateWindow()
    def refresh(self): self.choices=actions(self.paths,self.tools); self.hover=-1; self.update()
    def index(self, point):
        x,y=point.x()-185,point.y()-185
        if not 105 < math.hypot(x,y) < 175 or not self.choices: return -1
        return int(((math.atan2(y,x)+math.pi/2)%(2*math.pi))/(2*math.pi)*len(self.choices))
    def paintEvent(self, event):
        p=QPainter(self); p.setRenderHint(QPainter.Antialiasing)
        p.setPen(QColor('#476354')); p.setBrush(QColor('#14271f')); p.drawEllipse(10,10,350,350)
        count=len(self.choices)
        for i,action in enumerate(self.choices):
            a=(i+.5)*2*math.pi/count-math.pi/2; x,y=185+math.cos(a)*140,185+math.sin(a)*140
            p.setBrush(QColor('#c6f18a' if i==self.hover else '#284535')); p.setPen(Qt.NoPen); p.drawRoundedRect(QRectF(x-48,y-22,96,44),12,12)
            p.setPen(QColor('#122218' if i==self.hover else '#ffffff')); p.drawText(QRectF(x-48,y-22,96,44),Qt.AlignCenter,action.label)
        p.setPen(QColor('#d6e5d3'))
        text=self.choices[self.hover].label if self.hover>=0 else ('Drop files here' if not self.paths else 'No available actions' if not count else 'Choose an output')
        p.drawText(QRectF(70,220,230,50),Qt.AlignCenter|Qt.TextWordWrap,text)
        p.drawText(QRectF(70,285,230,50),Qt.AlignCenter,'PDF tools' if self.tools else 'Escape to dismiss')
    def mouseMoveEvent(self,event): self.hover=self.index(event.position()); self.bird.look=self.hover>=0; self.update()
    def mousePressEvent(self,event):
        index=self.index(event.position())
        if index>=0 and self.paths: self.submit(index)
        elif not self.paths: self.owner.pick(self.tools)
    def keyPressEvent(self,event):
        if event.key()==Qt.Key_Escape: self.hide()
    def dragEnterEvent(self,event):
        paths=[u.toLocalFile() for u in event.mimeData().urls() if u.isLocalFile() and Path(u.toLocalFile()).is_file()]
        if paths:
            self.paths=paths; self.refresh(); event.acceptProposedAction()
    def dragMoveEvent(self,event):
        self.hover=self.index(event.position()); self.bird.look=self.hover>=0; self.update()
        if self.hover>=0: event.acceptProposedAction()
        else: event.ignore()
    def dropEvent(self,event):
        index=self.index(event.position())
        if index>=0: event.acceptProposedAction(); QTimer.singleShot(0,lambda:self.submit(index))
        else: event.ignore()
    def submit(self,index):
        action=self.choices[index].key; options={}; self.hide()
        if action=='pdf-organize':
            value,ok=QInputDialog.getText(None,'Organize PDF','Pages to keep, in order (example: 3, 1-2):')
            if not ok:return
            options['pages']=value
        if action=='pdf-metadata':
            from pypdf import PdfReader
            try: metadata=PdfReader(self.paths[0]).metadata or {}
            except Exception as exc: QMessageBox.warning(None,'OpenLorikeet',str(exc)); return
            for key in ('title','author','subject','keywords'):
                value,ok=QInputDialog.getText(None,'PDF metadata',key.title()+':',text=str(metadata.get('/'+key.title(),'') or ''))
                if not ok:return
                options[key]=value
        self.owner.start(self.paths,action,options)


class App:
    def __init__(self):
        self.feedback=Feedback(); self.wheel=Wheel(self); self.pool=QThreadPool(); self.pool.setMaxThreadCount(2); self.jobs=[]
        self.tray=QSystemTrayIcon(QIcon(str(ASSETS/'lorikeet.png')))
        self.tray.setToolTip('OpenLorikeet'); menu=QMenu(); self.menu=menu
        for label,callback in [('Open conversion wheel',lambda:self.wheel.reveal()),('Convert files…',lambda:self.pick(False)),('PDF tools…',lambda:self.pick(True))]:
            menu.addAction(label,callback)
        menu.addSeparator()
        motion=QAction('Reduce motion',menu); motion.setCheckable(True); motion.setChecked(QSettings().value('reducedMotion',False,type=bool))
        motion.toggled.connect(lambda value:QSettings().setValue('reducedMotion',value)); menu.addAction(motion)
        menu.addAction('Engine status',lambda:QMessageBox.information(None,'Local engines','LibreOffice: '+('Ready' if office() else 'Install for Word → PDF')+'\nBuilt in: images, PDF tools, spreadsheets.'))
        menu.addAction('Quit',QApplication.quit); self.tray.setContextMenu(menu)
        self.tray.activated.connect(lambda reason:self.wheel.reveal() if reason==QSystemTrayIcon.Trigger else None); self.tray.show()
        self.poll=monitor(); self.was_pressed=False; self.timer=QTimer(); self.timer.timeout.connect(self.check); self.timer.start(65)
        if not QSystemTrayIcon.isSystemTrayAvailable():self.wheel.reveal()
    def check(self):
        pressed=self.poll() if self.poll else False
        if pressed and not self.was_pressed and not self.jobs:self.wheel.reveal()
        self.was_pressed=pressed
    def pick(self,tools):
        paths,_=QFileDialog.getOpenFileNames(None,'Choose local files')
        if paths:self.wheel.reveal(tools,paths)
    def start(self,paths,action,options):
        job=Job(list(paths),action,options); self.jobs.append(job)
        self.feedback.show_status('Converting locally…','working')
        job.signals.done.connect(lambda saved,errors:self.finished(job,saved,errors)); self.pool.start(job)
    def finished(self,job,saved,errors):
        self.jobs.remove(job)
        message=f'Saved {len(saved)} file(s).'
        if errors:message+='\n'+'\n'.join(errors)
        self.feedback.show_status(message,'failed' if errors else 'happy',saved)


def main():
    app=QApplication(sys.argv); app.setOrganizationName('OpenLorikeet'); app.setApplicationName('OpenLorikeet'); app.setQuitOnLastWindowClosed(False)
    app.setStyleSheet('QWidget { font-size: 13px; } QPushButton { padding: 7px; }')
    if '--self-test' in sys.argv:
        from PIL import Image
        from pypdf import PdfReader
        from docx import Document
        from openpyxl import Workbook
        from reportlab.pdfgen import canvas
        bird=Bird()
        if bird.atlas.isNull(): raise RuntimeError('Mascot artwork is missing')
        for pose in ('ready', 'working', 'happy', 'failed'):
            bird.set_pose(pose)
            if bird.grab().isNull(): raise RuntimeError('Mascot rendering failed')
        print('PASS: packaged imports, resources, and mascot rendering')
        return 0
    controller=App()
    return app.exec()
