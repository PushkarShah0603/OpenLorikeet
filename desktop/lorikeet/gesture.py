"""Read only modifier/button state. File contents arrive exclusively through Qt drops."""
import ctypes
import os
import sys


def monitor():
    if sys.platform == 'win32':
        user = ctypes.windll.user32
        return lambda: bool(user.GetAsyncKeyState(0x10) & 0x8000 and user.GetAsyncKeyState(0x01) & 0x8000)
    if sys.platform.startswith('linux') and os.environ.get('DISPLAY') and not os.environ.get('WAYLAND_DISPLAY'):
        from ctypes.util import find_library
        library = find_library('X11')
        if not library: return None
        x = ctypes.CDLL(library)
        x.XOpenDisplay.argtypes = [ctypes.c_char_p]; x.XOpenDisplay.restype = ctypes.c_void_p
        display = x.XOpenDisplay(None)
        if not display: return None
        x.XDefaultRootWindow.argtypes = [ctypes.c_void_p]; x.XDefaultRootWindow.restype = ctypes.c_ulong
        root = x.XDefaultRootWindow(display)
        x.XQueryPointer.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.c_ulong), *([ctypes.POINTER(ctypes.c_int)]*4), ctypes.POINTER(ctypes.c_uint)]
        def pressed():
            a, b = ctypes.c_ulong(), ctypes.c_ulong()
            coords = [ctypes.c_int() for _ in range(4)]; mask = ctypes.c_uint()
            ok = x.XQueryPointer(display, root, ctypes.byref(a), ctypes.byref(b), *(ctypes.byref(v) for v in coords), ctypes.byref(mask))
            return bool(ok and mask.value & 1 and mask.value & 256)
        return pressed
    return None
