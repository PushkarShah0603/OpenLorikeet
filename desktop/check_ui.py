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
