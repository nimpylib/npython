import ctypes
from math import cos, pi, sin

libc = ctypes.cdll['libc.so.6']
libm = ctypes.cdll['libm.so.6']

libm.sin.argtypes = [ctypes.c_double]
libm.sin.restype = ctypes.c_double

assert libm.sin(0.5) == sin(0.5)

libc.abs.argtypes = [ctypes.c_int]
libc.abs.restype = ctypes.c_int

assert libc.abs(-7) == 7

