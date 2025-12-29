import pyobject
import codeobject
import baseBundle
import dictobject
import tupleobject

declarePyType Function(tpToken):
  name{.dunder_member,readonly.}: PyStrObject
  code{.dunder_member,readonly.}: PyCodeObject
  globals{.dunder_member,readonly.}: PyDictObject
  closure{.dunder_member,readonly.}: PyTupleObject # could be nil
  defaults{.dunder_member,readonly.}: PyTupleObject # positional defaults tuple, could be nil
  kwdefaults{.dunder_member,readonly.}: PyDictObject

# forward declaretion
declarePyType BoundMethod(tpToken):
  fun: PyFunctionObject
  self: PyObject


proc newPyFunc*(name: PyStrObject, 
                code: PyCodeObject, 
                globals: PyDictObject,
                closure: PyTupleObject = nil,
                defaults: PyTupleObject = nil): PyFunctionObject = 
  result = newPyFunctionSimple()
  result.name = name
  result.code = code
  result.globals = globals
  result.closure = closure
  result.defaults = defaults
  result.kwdefaults = newPyDict()


proc newBoundMethod*(fun: PyFunctionObject, self: PyObject): PyBoundMethodObject = 
  result = newPyBoundMethodSimple()
  result.fun = fun
  result.self = self


implFunctionMagic get:
  newBoundMethod(self, other)


implBoundMethodMagic get:
  self

declarePyType StaticMethod():
  callable: PyObject

implStaticMethodMagic get:
  self.callable

implStaticMethodMagic init(callable: PyObject):
  self.callable = callable
  pyNone

proc newPyStaticMethod*(callable: PyObject): PyStaticMethodObject = 
  result = newPyStaticMethodSimple()
  result.callable = callable
