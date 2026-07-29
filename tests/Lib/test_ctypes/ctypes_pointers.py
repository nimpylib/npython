
import ctypes

char_p = ctypes.POINTER(ctypes.c_char)
assert char_p is ctypes.POINTER(ctypes.c_char)
assert char_p.__base__ is ctypes._Pointer

c = ctypes.c_char(b'a')
p = ctypes.pointer(c)
assert type(p) is char_p
assert p.contents is c

import sys
if sys.platform == 'win32': sys.exit()

libc = ctypes.cdll['libc.so.6']
libc.memset.argtypes = [char_p, ctypes.c_int, ctypes.c_size_t]
libc.memset.restype = char_p
res = libc.memset(p, 66, 1)
assert type(res) is char_p
assert c.value == b'B'

libc.memset(c, 67, 1)
assert c.value == b'C'
