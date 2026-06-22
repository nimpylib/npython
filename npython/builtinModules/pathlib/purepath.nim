
from pkg/pyrepr import pyrepr
import ../private/utils

impObjects [
  pyobject,
  exceptions,
  noneobject,
  bltcommon,
  stringobject,
]
import ./purepathDecl
export purepathDecl except fspath, getSep, with_path, addPart, partAsStr, init

methodMacroTmpl(PurePath)

implPurePathMagic init:
  retIfExc self.init(args)
  pyNone

method `$`*(self: PyPurePathObject): string{.raises: [].} = self.str
implPurePathMagic str: newPyStr $self
implPurePathMagic repr:
  var res = self.typeName
  res.add '('
  res.add pyrepr self.str
  res.add ')'
  newPyStr res

implPurePathMethod "__fspath__"(): newPyStr self.str


proc with_segments*[T: PyPurePathObject](self: T, segments: openArray[PyObject]): PyObject =
  let res = self.with_path""
  retIfExc res.init segments
  res

implPurePathMethod with_segments(*segments): self.with_segments segments

proc `/`*[T: PyPurePathObject](self: T, other: PyObject): PyObject = self.with_segments [self, other]

proc `/`*[T: PyPurePathObject](self: T, other: string): T =
  var res = self.str
  res.addPart other, self.getSep()
  let ret = self.with_path res
  T ret
proc `/`*[T: PyPurePathObject](self: T, other: T): T = self / other.str

implPurePathMagic trueDiv: self/other
