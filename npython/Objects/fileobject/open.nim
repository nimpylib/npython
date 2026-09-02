
include ./comm
import std/options
import ./decl
import ../exceptions/ioerror
import ../exceptions/oserr/convert
import ../[pyobject, pyobjectBase, exceptions, stringobject,
                      fileobject,
  ]
import ../bltcommon
import ../../Python/getargs/dispatch

macro openModeCase(mode: untyped; openWithMode: untyped): untyped =
  result = newNimNode(nnkCaseStmt).add(mode)
  for m in ["r", "w", "a", "x", "rb", "wb", "ab", "xb",
            "r+", "w+", "a+", "x+", "r+b", "w+b", "a+b", "x+b"]:
    result.add nnkOfBranch.newTree(newLit(m),
      newNimNode(nnkReturnStmt).add(newCall(openWithMode, newLit(m))))
  result.add nnkElse.newTree(newNimNode(nnkReturnStmt).add(
    newCall("newValueError", newCall("newPyAscii",
      newNimNode(nnkInfix).add(ident"&", newLit("invalid mode: "), mode)))))


proc open*(filename: PyStrObject, mode = "r", buffering = -1,
    encoding = pyio.DefEncoding, errors = pyio.DefErrors,
    newline = none string): PyObject {.bltin_clinicGen.} =
  let newline = if newline.isNone: pyio.DefNewLine else: newline.unsafeGet
  template openWithMode(m: static[string]): PyObject =
    handleIOErrRetPyObj: handleOsErrRetPyObj:
      try:
        newPyFile pyio.open($filename.str, m, buffering, encoding, errors, newline)
      except ValueError as e: return newValueError newPyStr e.msg
      except LookupError as e: return newLookupError newPyStr e.msg
  openModeCase mode, openWithMode
