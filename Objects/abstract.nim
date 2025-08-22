
import ./pyobject
import ./numobjects
import ./stringobject
import ../Python/call
export PyNumber_Index, PyNumber_AsSsize_t, PyNumber_AsClampedSsize_t


import ./abstract_without_call
export abstract_without_call


proc callMethod*(self: PyObject, name: PyStrObject, arg: PyObject): PyObject =
  ## `PyObject_CallMethodOneArg`
  assert not arg.isNil
  vectorcallMethod(name, [self, arg])
  
