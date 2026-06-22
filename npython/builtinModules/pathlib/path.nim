
import ../private/utils

impObjects [
  pyobject,
  exceptions,
  bltcommon,
  stringobject,
  byteobjects,
  noneobject,
  exceptions/ioerror,
  exceptions/oserr/convert,
  iterobject,
  #memoryobject,
]
import pkg/jscompat/syncio
import ../os/funcs/lists

import ./purepaths
export purepaths

declarePyType Path(base(PurePath)): discard

using self: PyPathObject

#TODO:encoding
proc write_text*(self; s: PyStrObject): PyBaseErrorObject =
  writeFileCompat self.str, s.asUTF8

proc write_text*(self; s: PyObject): PyBaseErrorObject =  
  if not s.ofPyStrObject:
    return newTypeError newPyStr("data must be str, not " & s.typeName)
  write_text self, PyStrObject(s)


implPathMethod write_text(s):
  handleIOErrRetPyObj:
    retIfExc self.write_text(s)
  pyNone

#[
proc write_bytes*(self; s: PyMemoryviewObject): PyBaseErrorObject =
  let p = s.mbuf.master.buf
  writeFileCompat self.str,

proc write_bytes*(self; s: PyObject): PyBaseErrorObject =  
  let mvE = newMemoryview(s)
  retIfExc mvE
  let mv = PyMemoryViewObject(mvE)
  write_bytes self, mv
]#


#TODO:encoding,errors,newline
proc read_text*(self): PyObject =
  var s: string
  handleIOErrRetPyObj:
    s = readFileCompat self.str
  newPyStr s

proc read_bytes*(self): PyObject =
  var s: string
  handleIOErrRetPyObj:
    s = readFileCompat self.str
  newPyBytes s

implPathMethod read_text: self.read_text
implPathMethod read_bytes: self.read_bytes

iterator iterdir*[T: PyPathObject](self: T): T =
  for entry in listdir self.str:
    yield self / entry

implPathMethod iterdir:
  newPyNimIteratorIter iterator(): PyObject{.raises: [].} =
    handleOsErrRetPyObj: 
      for i in self.iterdir: yield i
