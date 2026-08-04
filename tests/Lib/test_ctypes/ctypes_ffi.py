import ctypes
from math import cos, pi, sin
import sys

from utils import libcname, libmname

libc = ctypes.cdll[libcname]
libm = ctypes.cdll[libmname]

libm.sin.argtypes = [ctypes.c_double]
libm.sin.restype = ctypes.c_double

assert libm.sin(0.5) == sin(0.5)

libc.abs.argtypes = [ctypes.c_int]
libc.abs.restype = ctypes.c_int

assert libc.abs(-7) == 7


compare_type = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p)

callback_calls = []

def compare(left, right):
    callback_calls.append(left - right)
    return left - right

values = (ctypes.c_int * 4)(4, 1, 3, 2)
libc.qsort.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_size_t, compare_type]
libc.qsort.restype = None
libc.qsort(ctypes.addressof(values), 4, ctypes.sizeof(ctypes.c_int), compare_type(compare))
assert len(callback_calls) > 0

def increment(value):
    return value + 1

identity_type = ctypes.PYFUNCTYPE(ctypes.c_int, ctypes.c_int)
assert identity_type(increment)(4) == 5

if sys.platform == "win32":
  win_identity_type = ctypes.WINFUNCTYPE(ctypes.c_int, ctypes.c_int)
  assert win_identity_type(increment)(4) == 5
