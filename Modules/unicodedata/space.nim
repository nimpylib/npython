#XXX:
#[As of 2.3.1, isSpace in `std/unicode` checks against 25 kinds of whitespaces,
in which:

* 0x001C: FILE SEPARATOR
* 0x001D: GROUP SEPARATOR
* 0x001E: RECORD SEPARATOR
* 0x001F: UNIT SEPARATOR

  are not regarded as whitespaces, while CPython thinks they are.

And std/unicode lacks isSpace for Rune
]#
import ./private/consts
import ./rune_decl
proc isspace*(r: Rune): bool = r.int in spaces
