import ctypes

Int3 = ctypes.c_int * 3
assert Int3 is ctypes.c_int * 3
assert Int3.__base__ is ctypes._Array
assert Int3._type_ is ctypes.c_int
assert Int3._length_ == 3
assert ctypes.sizeof(Int3) == ctypes.sizeof(ctypes.c_int) * 3

a = Int3(1, 2)
assert len(a) == 3
assert a[0] == 1
assert a[1] == 2
assert a[2] == 0
assert a[-1] == 0

a[1] = 9
assert a[1] == 9
a[2] = ctypes.c_int(7)
assert a[2] == 7

assert ctypes.addressof(a) != 0

Int3b = 3 * ctypes.c_int
assert Int3b is Int3

Matrix = Int3 * 2
m = Matrix(Int3(1, 2, 3))
assert m[0][1] == 2
m[0][1] = 5
assert m[0][1] == 5
