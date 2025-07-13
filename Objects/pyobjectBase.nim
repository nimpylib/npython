import strformat
import strutils
import macros
import tables

import ../Utils/utils

type
  PyTypeToken* {. pure .} = enum
    NULL,
    Object,
    None,
    BaseError, # exception
    Int,
    Float,
    Bool,
    Type,
    Tuple,
    List,
    Str,
    Code,
    NimFunc,
    Function,
    BoundMethod,
    Slice,
    Cell,
    Set,
    FrozenSet,

when defined(js):
  var objectId = 0

type 
  # function prototypes, magic methods tuple, PyObject and PyTypeObject
  # rely on each other, so they have to be declared in the same `type`

  # these three function are used when number of arguments can be
  # directly obtained from OpCode
  UnaryMethod* = proc (self: PyObject): PyObject {. cdecl .}
  BinaryMethod* = proc (self, other: PyObject): PyObject {. cdecl .}
  TernaryMethod* = proc (self, arg1, arg2: PyObject): PyObject {. cdecl .}


  # for those that number of arguments unknown (and potentially kwarg?)
  BltinFunc* = proc (args: seq[PyObject]): PyObject {. cdecl .}
  BltinMethod* = proc (self: PyObject, args: seq[PyObject]): PyObject {. cdecl .}


  MagicMethods* = tuple
    add: BinaryMethod
    sub: BinaryMethod
    mul: BinaryMethod
    trueDiv: BinaryMethod
    floorDiv: BinaryMethod
    # use uppercase to avoid conflict with nim keywords
    # backquoting is a less clear solution
    Mod: BinaryMethod
    pow: BinaryMethod
    
    Not: UnaryMethod
    negative: UnaryMethod
    positive: UnaryMethod
    abs: UnaryMethod
    index: UnaryMethod
    bool: UnaryMethod

    # note: these 3 are all bitwise operations, nothing to do with keywords `and` or `or`
    And: BinaryMethod
    Xor: BinaryMethod
    Or: BinaryMethod

    lt: BinaryMethod
    le: BinaryMethod
    eq: BinaryMethod
    ne: BinaryMethod
    gt: BinaryMethod
    ge: BinaryMethod
    contains: BinaryMethod

    len: UnaryMethod

    str: UnaryMethod
    repr: UnaryMethod

    New: BltinFunc  # __new__ is a `staticmethod` in Python
    init: BltinMethod
    getattr: BinaryMethod
    setattr: TernaryMethod
    hash: UnaryMethod
    call: BltinMethod 

    # subscription
    getitem: BinaryMethod
    setitem: TernaryMethod

    # descriptor protocol
    # what to do when getting or setting attributes of its intances
    get: BinaryMethod
    set: TernaryMethod
    
    # what to do when `iter` or `next` are operating on its instances
    iter: UnaryMethod
    iternext: UnaryMethod


  PyObject* = ref object of RootObj
    when defined(js):
      id: int
    pyType*: PyTypeObject
    # the following fields are possible for a PyObject
    # depending on how it's declared (mutable, dict, etc)
    
    # prevent infinite recursion evaluating repr
    # reprLock*: bool
    
    # might be used to avoid GIL in the future?
    # a semaphore and a mutex...
    # but Nim has only thread local heap...
    # maybe interpreter level thread?
    # or real pthread but kind of read-only, then what's the difference with processes?
    # or both?
    # readNum*: int
    # writeLock*: bool

  # todo: document
  PyObjectWithDict* = ref object of PyObject
    # this is actually a PyDictObject. but we haven't defined dict yet.
    # the values are set in typeobject.nim when the type is ready
    dict*: PyObject

  PyTypeObject* = ref object of PyObjectWithDict
    name*: string
    base*: PyTypeObject
    # corresponds to `tp_flag` in CPython. Why not use bit operations? I don't know.
    # Both are okay I suppose
    kind*: PyTypeToken
    magicMethods*: MagicMethods
    bltinMethods*: Table[string, BltinMethod]
    getsetDescr*: Table[string, (UnaryMethod, BinaryMethod)]

# add underscores
macro genMagicNames: untyped = 
  let bracketNode = nnkBracket.newTree()
  var m: MagicMethods
  for name, v in m.fieldpairs:
    bracketNode.add newLit("__" & name.toLowerAscii & "__")

  nnkStmtList.newTree(
    nnkConstSection.newTree(
      nnkConstDef.newTree(
        nnkPostfix.newTree(
          ident("*"),
          newIdentNode("magicNames"),
        ),
        newEmptyNode(),
        bracketNode
      )
    )
  )

genMagicNames


method `$`*(obj: PyObject): string {.base, inline.} = 
  "Python object"

proc id*(obj: PyObject): int {. inline, cdecl .} = 
  when defined(js):
    obj.id
  else:
    cast[int](obj)

when defined(js):
  proc giveId*(obj: PyObject) {. inline, cdecl .} =
    obj.id = objectId
    # id depleted? not likely
    inc objectId


proc idStr*(obj: PyObject): string {. inline .} = 
  fmt"{obj.id:#x}"


# record builtin types defined. Make them ready for Python level usage in typeReady
var bltinTypes*: seq[PyTypeObject]


proc newPyTypePrivate(name: string): PyTypeObject = 
  new result
  when defined(js):
    result.giveId
  result.name = name
  result.bltinMethods = initTable[string, BltinMethod]()
  result.getsetDescr = initTable[string, (UnaryMethod, BinaryMethod)]()
  bltinTypes.add(result)


let pyObjectType* = newPyTypePrivate("object")


proc newPyType*(name: string): PyTypeObject =
  result = newPyTypePrivate(name)
  result.base = pyObjectType

proc hasDict*(obj: PyObject): bool {. inline .} = 
  obj of PyObjectWithDict

proc getDict*(obj: PyObject): PyObject {. cdecl .} = 
  if not obj.hasDict:
    unreachable("obj has no dict. Use hasDict before getDict")
  PyObjectWithDict(obj).dict

proc isClass*(obj: PyObject): bool {. cdecl .} = 
  obj.pyType.kind == PyTypeToken.Type
