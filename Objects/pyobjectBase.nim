import strformat
import strutils
import macros
import tables

import ../Utils/[utils, rtarrays]
export rtarrays
import ../Include/descrobject

type
  PyTypeToken* {. pure .} = enum
    NULL,
    Object,
    None,
    Ellipsis,
    BaseException, # BaseException
    Int,
    Float,
    Bool,
    Type,
    Tuple,
    List,
    Dict,
    Bytes,
    Str,
    Code,
    NimFunc,
    Function,
    BoundMethod,
    Slice,
    Cell,
    Set,
    FrozenSet,

macro pyCFuncPragma*(def): untyped =
  ## equiv for `{.pragma: pyCFuncPragma, cdecl, raises: [].}` but is exported
  var p = def.pragma
  if p.kind == nnkEmpty: p = newNimNode nnkPragma
  def.pragma = p
    .add(ident"cdecl")
    .add(nnkExprColonExpr.newTree(
      ident"raises", newNimNode nnkBracket  # raises: []
    ))
  def

template pyDestructorPragma*(def): untyped = pyCFuncPragma(def)

type 
  # function prototypes, magic methods tuple, PyObject and PyTypeObject
  # rely on each other, so they have to be declared in the same `type`

  # these three function are used when number of arguments can be
  # directly obtained from OpCode
  UnaryMethod* = proc (self: PyObject): PyObject {. pyCFuncPragma .}
  BinaryMethod* = proc (self, other: PyObject): PyObject {. pyCFuncPragma .}
  TernaryMethod* = proc (self, arg1, arg2: PyObject): PyObject {. pyCFuncPragma .}


  # for those that number of arguments unknown (and potentially kwarg?)
  BltinFunc* = proc (args: seq[PyObject]): PyObject {. pyCFuncPragma .}
  BltinMethod* = proc (self: PyObject, args: seq[PyObject]): PyObject {. pyCFuncPragma .}


  destructor* = proc (arg: var PyObjectObj){.pyDestructorPragma.}
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
    
    iadd,
      isub,
      imul,
      itrueDiv,
      ifloorDiv,
      # use uppercase to avoid conflict with nim keywords
      # backquoting is a less clear solution
      iMod,
      ipow,
      # note: these 3 are all bitwise operations, nothing to do with keywords `and` or `or`
      iAnd,
      iXor,
      iOr: BinaryMethod

    Not: UnaryMethod
    negative: UnaryMethod
    positive: UnaryMethod
    abs: UnaryMethod
    index: UnaryMethod
    bool: UnaryMethod
    int: UnaryMethod
    float: UnaryMethod

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
    bytes: UnaryMethod
    repr: UnaryMethod

    New: BltinFunc  # __new__ is a `staticmethod` in Python
    init: BltinMethod

    del: UnaryMethod  ##[XXX: tp_del is deprecated over tp_finalize,
      but NPython uses `del` to mean tp_finalize
      (has to use the non-dunder name to ensure `magicNames` is correct)
    ]##

    getattr: BinaryMethod
    setattr: TernaryMethod
    delattr: BinaryMethod
    hash: UnaryMethod
    call: BltinMethod 

    # subscription
    getitem: BinaryMethod
    setitem: TernaryMethod
    delitem: BinaryMethod

    # descriptor protocol
    # what to do when getting or setting attributes of its intances
    get: BinaryMethod
    set: TernaryMethod
    
    # what to do when `iter` or `next` are operating on its instances
    iter: UnaryMethod
    iternext: UnaryMethod


  PyObjectObj* = object
    ## unstable
    when defined(js):
      id: int
    pyType*: PyTypeObject
    finalized: bool  ## inner
    finalizing: uint8 ## inner. may be 0,1,2
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

  PyObject* = ref object of RootObj
    pybase_head: PyObjectObj

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
    members*: RtArray[PyMemberDef]
    magicMethods*: MagicMethods
    bltinMethods*: Table[string, BltinMethod]
    getsetDescr*: Table[string, (UnaryMethod, BinaryMethod)]
    tp_dealloc*: destructor
    tp_alloc*: proc (self: PyTypeObject, nitems: int): PyObject{.pyCFuncPragma.}  ## XXX: currently must not return exception
    tp_basicsize*: int ## NPython won't use var-length struct, so no tp_itemsize needed.

template def_tp_alloc(body): untyped{.dirty.} =
  proc (self: PyTypeObject, nitems: int): PyObject{.pyCFuncPragma.} = body
  
template tp_free*(self: PyTypeObject; op: var PyObjectObj) = discard  ## current no need

genTypeToAnyKind PyObject

proc `=destroy`(self: var PyObjectObj) =
  if self.pyType.isNil: return
  let fun = self.pyType.tp_dealloc
  if fun.isNil: return
  fun(self)

template finalized(self: PyObject): bool = self.pybase_head.finalized
proc callTpDel*[Py: PyObject](tp: PyTypeObject; obj: var PyObjectObj): PyObject =
  ## inner
  template tp(t: PyTypeObject): untyped = t.magicMethods
  var o = new Py
  o.pybase_head = obj
  result = tp.tp.del(o)
  obj.finalized = o.finalized

template callOnceFinalizerFromDealloc*(self: var PyObjectObj; callBody) =
  if self.finalized: return
  self.finalizing.inc
  if self.finalizing > 1: return
  callBody
  self.finalized = true

template pyType*(self: PyObject): PyTypeObject = self.pybase_head.pyType

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


template typeName*(o: PyObject): string =
  o.pyType.name

method `$`*(obj: PyObject): string {.base, pyCFuncPragma.} =
  result = "Python object "
  if obj.pyType.isNil:
    result.add "of unknown pytype(nil)"
  else:
    result.add "of pytype "
    result.add obj.typeName
    # we wanna use `__repr__` if possible
    let fun = obj.pyType.magicMethods.repr
    if not fun.isNil:
      let ret = fun(obj)
      # XXX: we haven't declared PyStr here
      #  so cannot use ofPyStrObject
      if ret.pyType.kind == Str:
        return $ret
      # exception occurs, just discard

proc id*(obj: PyObject): int {. inline, cdecl .} = 
  when defined(js):
    obj.pybase_head.id
  else:
    cast[int](obj)


when defined(js):
  var objectId = 0
  proc giveId*(obj: PyObject) {. inline, cdecl .} =
    obj.pybase_head.id = objectId
    # id depleted? not likely
    inc objectId


proc idStr*(obj: PyObject): string {. inline .} = 
  fmt"{obj.id:#x}"


# record builtin types defined. Make them ready for Python level usage in typeReady
var bltinTypes*: seq[PyTypeObject]


proc newPyTypePrivate[T: PyObject](name: string): PyTypeObject = 
  new result
  when defined(js):
    result.giveId
  result.name = name
  result.bltinMethods = initTable[string, BltinMethod]()
  result.getsetDescr = initTable[string, (UnaryMethod, BinaryMethod)]()
  bltinTypes.add(result)
  result.tp_basicsize = sizeof T
  result.tp_alloc = def_tp_alloc:
    let res = new T
    res.pyType = self
    res


let pyObjectType* = newPyTypePrivate[PyObject]("object")


proc newPyType*[T: PyObject](name: string, base = pyObjectType): PyTypeObject =
  result = newPyTypePrivate[T](name)
  result.base = base

proc hasDict*(obj: PyObject): bool {. inline .} = 
  obj of PyObjectWithDict

proc getDictUnsafe*(obj: PyObject): PyObject {. cdecl .} = 
  ## assuming obj.hasDict
  PyObjectWithDict(obj).dict
  
proc getDict*(obj: PyObject): PyObject {. cdecl .} = 
  if not obj.hasDict:
    unreachable("obj has no dict. Use hasDict before getDict")
  obj.getDictUnsafe

proc isClass*(obj: PyObject): bool {. cdecl .} = 
  obj.pyType.kind == PyTypeToken.Type

proc ofPyTypeObject*(obj: PyObject): bool {. cdecl .} = obj.isClass
proc isType*(a, b: PyTypeObject): bool {. cdecl .} = system.`==`(a, b)

