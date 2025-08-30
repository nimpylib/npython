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

# forward declaretion
declarePyType BoundMethod(tpToken):
  fun: PyFunctionObject
  self: PyObject


proc newPyFunc*(name: PyStrObject, 
                code: PyCodeObject, 
                globals: PyDictObject,
                closure: PyObject = nil): PyFunctionObject = 
  result = newPyFunctionSimple()
  result.name = name
  result.code = code
  result.globals = globals
  if not closure.isNil:
    assert closure.ofPyTupleObject()
  result.closure = PyTupleObject(closure)


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
