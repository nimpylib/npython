
import ./pyimp
impObjects [
  pyobject,
  typeobject,
]
imp Utils, [destroyPatch]
import pkg/libffi
type
  CTypeKind* = enum
    ckVoid,
    ckBool,
    ckSigned,
    ckUnsigned,
    ckFloat,
    ckDouble,
    ckPointer,
    ckCString,
    ckCWString,

type
  CTypeInfo* = object
    kind*: CTypeKind
    ffiType*: ptr Type
    target*: PyTypeObject

  FFIValue* = object
    kind*: CTypeKind
    p*: pointer
    pIsAlloced*: bool
    p2pIsAlloced*: bool
    keepalive*: PyObject
defdestroy FFIValue:
  if self.p2pIsAlloced:
    dealloc (cast[ptr pointer](self.p))[]
  if self.pIsAlloced: dealloc self.p

