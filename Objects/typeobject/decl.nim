
import ../pyobjectBase

let pyTypeObjectType* = newPyType[PyTypeObject]("type")
# NOTE:
#[
type.__base__ is object
type(type) is type
object.__base__ is None
]# 
pyTypeObjectType.kind = PyTypeToken.Type
