

import pyobject
import exceptions


import stringobject

type
  NFunc* {. pure .} = enum
    BltinFunc,  # general function, no self
    # methods with a `self` attribute
    UnaryMethod,   # method with 1 arg
    BinaryMethod,  # method with 2 args
    TernaryMethod, # method with 3 args
    BltinMethod,   # method with arbitary args

    # mixing function and method is to some extent unnatural
    # however, this makes function and method call dispatch most efficient

declarePyType NimFunc(tpToken):
    name: PyStrObject
    self: PyObject  # not set for BltinFunc
    kind: NFunc
    fun: int  # generic function pointer, determined by kind
                  

implNimFuncMagic call:
  case self.kind
  of NFunc.BltinFunc:
    return cast[BltinFunc](self.fun)(args)
  of NFunc.UnaryMethod:
    checkArgNum(0)
    return cast[UnaryMethod](self.fun)(self.self)
  of NFunc.BinaryMethod:
    checkArgNum(1)
    return cast[BinaryMethod](self.fun)(self.self, args[0])
  of NFunc.TernaryMethod:
    checkArgNum(2)
    return cast[TernaryMethod](self.fun)(self.self, args[0], args[1])
  of NFunc.BltinMethod:
    return cast[BltinMethod](self.fun)(self.self, args)


# diff with methods: no `self` init
proc newPyNimFunc*(fun: BltinFunc, name: PyStrObject): PyNimFuncObject =
  result = newPyNimFuncSimple()
  result.name = name
  result.kind = NFunc.BltinFunc
  result.fun = cast[int](fun)
  

template newMethodTmpl(FunType) = 
  proc newPyNimFunc*(fun: FunType, name: PyStrObject, self:PyObject=nil): PyNimFuncObject = 
    # `self` should never be nil. The default arg here is to fool the compiler 
    # when initializing type dict
    assert (not self.isNil)
    result = newPyNimFuncSimple()
    result.name = name
    result.kind = NFunc.FunType
    result.fun = cast[int](fun)
    result.self = self


newMethodTmpl(UnaryMethod)
newMethodTmpl(BinaryMethod)
newMethodTmpl(TernaryMethod)
newMethodTmpl(BltinMethod)
