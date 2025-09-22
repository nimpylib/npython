## this module is splited from ./meth to get rid of 
import std/strformat
import ../../[
  pyobject,
  exceptions,
  stringobject,
  listobject, tupleobject,
]

from ../../abstract/sequence/list import PySequence_Fast
import ../../../Include/cpython/critical_section

proc join*[T: PyStrObject|PyObject](self: PyStrObject; items: openArray[T]): PyObject =
  ## `_PyUnicode_JoinArray`
  const mayNotAllStr = T is_not PyStrObject
  var sep: PyStrObject = self
  var seplen: int
  var resAscii = false
  var last_obj: PyStrObject = nil
  case items.len
  of 0: return newPyAscii()
  of 1:
    when mayNotAllStr:
      let e = items[0]
      if e.ofExactPyStrObject: return e
      seplen = 0
      resAscii = true
    else:
      return items[0]
  else:
    # Set up sep and seplen
    if sep.isNil:
      # fall back to a blank space separator
      sep = newPyStr ' '
      seplen = 1
      resAscii = true
    else:
      seplen = sep.len
      resAscii = sep.isAscii
    last_obj = sep
  #[There are at least two things to join, or else we have a subclass
  of str in the sequence.
  Do a pre-pass to figure out the total amount of space we'll
  need (sz), (we've know all arguments are strings).]#
  const mayMemcpy = declared(copyMem)
  var
    sz = 0
    add_sz: int
  when mayMemcpy:
    var use_memcpy = true
  for i, item in items:
    {.push overflowChecks: off.}
    when mayNotAllStr:
      if not item.ofPyStrObject:
        return newTypeError newPyStr(fmt"sequence item {i}: expected str instance, {item.typeName:.80s} found")
      let item = PyStrObject item
    add_sz = item.len
    resAscii = resAscii and item.isAscii
    if i > 0:
      add_sz += seplen
    if add_sz > int.high - sz:
      return newOverflowError newPyAscii"join() result is too long for a Python string"
    sz += add_sz
    when mayMemcpy:
      if use_memcpy and not item.isNil:
        if last_obj.isAscii != item.isAscii:
          use_memcpy = false
        last_obj = item
    {.pop.}
  var res = newPyStr(sz, resAscii)

  let itemSize = res.itemSize
  # Catenate everything.
  template loopAdd(cb) =
    var res_start = 0
    for i, item in items:
      # Copy item, and maybe the separator.
      if i > 0 and seplen > 0:
        cb(res, res_start, sep, 0, seplen)
        res_start += seplen
      when mayNotAllStr:
        let item = PyStrObject item
      let itemlen = item.len
      if itemlen > 0:
        cb(res, res_start, item, 0, itemlen)
        res_start += itemlen
  when mayMemcpy:
    if use_memcpy:
      assert res.itemSize == sep.itemSize
      template copyImpl(dest, dest_start, frm, frm_start, how_many) =
        copyMem(dest[dest_start].addr, frm[frm_start].addr, itemSize * how_many)
      template gen(fld){.dirty.} =
        template `copy fld`(dest, dest_start, frm, frm_start, how_many) =
          copyImpl(dest.str.fld, dest_start, frm.str.fld, frm_start, how_many)
      gen asciiStr
      gen unicodeStr
      if res.itemSize == 1: loopAdd copyAsciiStr
      else: loopAdd copyUnicodeStr
    else:
      loopAdd fastCopyCharacters
  else:
    loopAdd fastCopyCharacters
  res

proc join*(self: PyStrObject; sequ: PyObject): PyObject =
  let fseq = PySequence_Fast(sequ, "can only join an iterable")
  retIfExc fseq
  template doAs(T) =
    let obj = `Py T Object` fseq
    criticalRead obj:
      result = self.join(obj.items)
  if fseq.ofPyListObject:
    doAs List
  else:
    result = self.join(PyTupleObject(fseq).items)

