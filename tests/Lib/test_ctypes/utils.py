
import sys
if sys.platform == 'win32':
    libcname = 'msvcrt.dll'
    libmname = 'msvcrt.dll'
elif sys.platform == 'linux':
    libcname = 'libc.so.6'
    libmname = 'libm.so.6'
#elif sys.platform == 'darwin':
else:
    libcname = 'libc.dylib'
    libmname = 'libm.dylib'
