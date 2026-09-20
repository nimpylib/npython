
import ../[
  pyobject,
  byteobjects,
]
import ../numobjects/intobject

template PyNumber_AsCharOr*(vv: PyObject, errSubject="byte"; orDoIt): char =
  bind PyNumberAsClampedSsize_t, checkCharRangeOrRetVE
  var value: int
  block:
    let it{.inject.} = PyNumber_AsClampedSsize_t(vv, value)
    if not it.isNil:
      orDoIt
  checkCharRangeOrRetVE(value, errSubject)
  cast[char](value)

template PyNumber_AsCharOrRet*(vv: PyObject, errSubject="byte"): char =
  PyNumber_AsCharOr(vv, errSubject):
    return it
