
import ./pyobject
import ./numobjects/intobject/decl
import pkg/intobject

declarePyType Bool(tpToken, typeName("bool"), base(Int), singleton):
  b: bool

proc newPyBoolInner(b: bool, v: IntObject): PyBoolObject = 
  result = newPyBoolSimple()
  result.b = b
  result.v = v  # ensure `int(b)` works


let pyTrueObj* =  newPyBoolInner(true, intOne)  ## singleton
let pyFalseObj* = newPyBoolInner(false,intZero)  ## singleton

proc newPyBool*(b: bool): PyBoolObject =
  if b: pyTrueObj
  else: pyFalseObj

proc isPyTrue*(self: PyBoolObject): bool = system.`==`(self, pyTrueObj)
