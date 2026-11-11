"""Headless resource and widget rendering check; real OS drag acceptance is separate."""
from PySide6.QtWidgets import QApplication
from lorikeet.app import Bird, Wheel

app = QApplication([])
bird = Bird()
assert not bird.atlas.isNull(), 'Mascot artwork is missing'
for pose in ('ready','working','happy','failed'):
    bird.set_pose(pose)
    assert not bird.grab().isNull()
class Owner:
    def pick(self, tools): pass
wheel = Wheel(Owner())
wheel.paths = ['example.png']; wheel.refresh()
assert any(a.key == 'pdf' for a in wheel.choices)
assert not wheel.grab().isNull()
assert wheel.index(wheel.rect().center()) == -1
print('PASS: mascot states, bundled assets, wheel rendering and center rejection')

from PySide6.QtTest import QTest
from PySide6.QtCore import Qt
selected = []
wheel.submit = selected.append
QTest.keyClick(wheel, Qt.Key_Right)
assert wheel.hover == 0
QTest.keyClick(wheel, Qt.Key_Return)
assert selected == [0], 'Keyboard selection must choose the highlighted action'
print('PASS: keyboard wheel navigation and selection')
