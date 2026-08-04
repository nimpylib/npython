
import ctypes

char_p = ctypes.POINTER(ctypes.c_char)
assert char_p is ctypes.POINTER(ctypes.c_char)
assert char_p.__base__ is ctypes._Pointer

c = ctypes.c_char(b'a')
p = ctypes.pointer(c)
assert type(p) is char_p
assert p.contents is c

res = ctypes.memset(ctypes.addressof(c), 66, 1)
assert res == ctypes.addressof(c)
assert c.value == b'B'

ctypes.memset(ctypes.addressof(c), 67, 1)
assert c.value == b'C'
