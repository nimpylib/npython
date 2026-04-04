
import ../[
  pyobject,
  exceptions,
  stringobject,
  hash,
  boolobject,
]
import ../numobjects/intobject_decl

# some generic behaviors that every type should obey
proc leDefault*(o1, o2: PyObject): PyObject {. pyCFuncPragma .} =
  let lt = o1.callMagic(lt, o2)
  let eq = o1.callMagic(eq, o2)
  lt.callMagic(Or, eq)

proc neDefault*(o1, o2: PyObject): PyObject {. pyCFuncPragma .} =
  let eq = o1.callMagic(eq, o2)
  eq.callMagic(Not)

proc gtDefault*(o1, o2: PyObject): PyObject {. pyCFuncPragma .} = 
  o2.callMagic(lt, o1)

proc geDefault*(o1, o2: PyObject): PyObject {. pyCFuncPragma .} = 
  let gt = o1.callMagic(gt, o2)
  let eq = o1.callMagic(eq, o2)
  gt.callMagic(Or, eq)

proc hashDefault*(self: PyObject): PyObject {. pyCFuncPragma .} = 
  let res = cast[BiggestInt](rawHash(self))  # CPython does so
  newPyInt(res)

proc eqDefault*(o1, o2: PyObject): PyObject {. pyCFuncPragma .} = 
  if rawEq(o1, o2): pyTrueObj
  else: pyFalseObj
