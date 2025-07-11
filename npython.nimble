version       = "0.1.0"
author        = "Weitang Li"
description   = "(Subset of) Python programming language implemented in Nim"
license       = "CPython license"
srcDir        = "Python"
bin           = @["python"]
binDir        = "bin"

requires  "cligen", "regex"
requires  "nim >= 1.6.14"  # 2.* (at least till 2.3.1) is okey, too.
