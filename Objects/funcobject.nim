import pyobject
import codeobject
import baseBundle
import dictobject
import tupleobject
import ../Include/internal/pycore_global_strings

declarePyType Function(tpToken):
  name{.dunder_member.}: PyStrObject
  module{.dunder_member,nil2none.}: PyObject
  code{.dunder_member.}: PyCodeObject
  globals{.dunder_member,readonly.}: PyDictObject
  closure{.dunder_member,readonly,nil2none.}: PyTupleObject # could be nil
  defaults{.dunder_member.}: PyTupleObject # positional defaults tuple, could be nil
  kwdefaults{.dunder_member.}: PyDictObject

# forward declaretion
declarePyType BoundMethod(tpToken):
  fun{.member"__func__", readonly.}: PyFunctionObject
  self{.dunder_member,readonly.}: PyObject

genProperty BoundMethod, "__name__", name, self.fun.name
genProperty BoundMethod, "__module__", module, self.fun.module.nil2none

proc newPyFunc*(name: PyStrObject, 
                code: PyCodeObject, 
                globals: PyDictObject,
                closure: PyTupleObject = nil,
                defaults: PyTupleObject = nil): PyFunctionObject = 
  
  result = newPyFunctionSimple()
  # __module__: Use globals['__name__'] if it exists, or NULL.
  var module: PyObject
  if globals.getItemRef(pyDUId(name), module):
    result.module = module
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
