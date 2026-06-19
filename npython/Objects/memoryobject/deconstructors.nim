
import std/strformat
import ../[
  pyobject,
  exceptions,
  bltcommon,
  noneobject,
  stringobject,
  pybuffer,
]
import ../abstract/pybuffer
import ../../Include/cpython/pyatomic

import ./decl

methodMacroTmpl(memoryview)

proc mbuf_release(self: PyManagedBufferObject) {.pyCFuncPragma.} =
  if self.flags & PyManagedBufferFlags.RELEASED:
    return
  self.flags = self.flags or PyManagedBufferFlags.RELEASED
  let exc = PyBuffer_Release self.master
  assert exc.isNil, "PyBuffer_Release failed in mbuf_release"

proc mbuf_dealloc(self: PyManagedBufferObject) {.cdecl.} =
  #XXX:BY-PASS: Nim may destroy MemoryView.mbuf before MemoryView's PyObject deallocator
  # has decremented this logical export count.
  #assert self.exports == 0, $self.exports
  mbuf_release self
  if self.flags & PyManagedBufferFlags.FREE_FORMAT:
    when not defined(js):
      dealloc self.master.format

proc mbuf_dealloc(self: var PyObjectObj) {.cdecl.} =
  mbuf_dealloc getPyHeapRef[PyManagedBufferObject](self)
pyManagedBufferObjectType.tp_dealloc = mbuf_dealloc

using self: PyMemoryViewObject
proc get_exports(self): int = Py_atomic_load_relaxed addr self.exports
proc releaseAux(self){.pyCFuncPragma.} =
  ## `_memory_release`
  assert self.get_exports == 0
  if self.flags & PyMemoryViewFlags.RELEASED:
    return
  self.flags = self.flags or PyMemoryViewFlags.RELEASED
  if self.mbuf.isNil: return
  if self.mbuf.exports > 0:
    dec self.mbuf.exports
  if self.mbuf.exports == 0:
    mbuf_release self.mbuf

proc release*(self): PyBaseErrorObject{.pyCFuncPragma.} =
  let exports = self.get_exports
  if exports == 0:
    self.releaseAux()
    return
  if exports > 0:
    var msg = fmt"memoryview has {exports} exported buffer"
    if exports > 1: msg.add 's'
    return newBufferError newPyAscii(msg)
  return newSystemError newPyAscii"memoryview: negative export count"

implMemoryviewMethod release():
  retIfExc self.release()
  pyNone

proc memory_releasebuf(self; _: PyObject) =
  discard Py_atomic_add(self.exports.addr, -1)

implMemoryviewMagic release_buffer:
  self.memory_releasebuf other
  pyNone

proc memory_dealloc(selfo: var PyObjectObj) {.cdecl.} =
  let self = getPyHeapRef[PyMemoryViewObject](selfo)
  assert self.get_exports == 0
  self.releaseAux()
pyMemoryViewObjectType.tp_dealloc = memory_dealloc
