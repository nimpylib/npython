import ctypes
from ctypes import c_char_p, c_int

assert type(ctypes.c_int) is type
assert type(ctypes.c_char_p) is type
assert ctypes.c_int.__base__ is ctypes._SimpleCData
assert ctypes.c_char_p.__base__ is ctypes._SimpleCData
assert c_int is ctypes.c_int
assert c_char_p is ctypes.c_char_p

i = c_int(3)
assert i.value == 3
assert repr(i) == "c_int(3)"
i.value = 4
assert i.value == 4

p = c_char_p(b"abc")
assert p.value == b"abc"
assert repr(p) == "c_char_p(b'abc')"

