
import ./initUtils
import ../../Include/pymacro
import ../../Objects/[
  hash as pyhash,
  dictobject,
  tupleobjectImpl,
  #boolobject,
  structseq,
  #namespaceobject,
]
import ../../Objects/numobjects/floatobject
import ../../Objects/numobjects/intobject/floatinfos
import ../../Python/[
  getversion,
]
template SetIntFlag(flag) = SetFlag newPyInt flag
template SetDblFlag(flag) = SetFlag newPyFloat flag
template SetAscFlag(flag) = SetFlag newPyAscii flag
template genInfo(pureNameId; qualname: string, docStr; fields; n; doIt){.dirty.} =
  PyDoc_STRVAR `pureNameId Info doc`, docStr

  var `pureNameId Info Type`* = new PyTypeObject  # XXX:
  # here CPython uses `static PyTypeObject VersionInfoType;`
  # (note in C `VersionInfoType` is a struct)
  const `pureNameId Info desc`* = newPyStructSequence_Desc(
      qualname,
      `pureNameId Info doc`,
      fields,
      n
  )

  proc `get pureNameId Info`*: PyObject =
    let maye = newPyStructSequence `pureNameId Info Type`
    retIfExc maye
    let it{.inject.} = PyStructSequenceObject maye

    var pos = 0
    template SetFlag(flag) =
      it[pos] = flag
      pos.inc
    doIt
    it

template genInfo(pureNameId; qualname: string, docStr; fields; doIt){.dirty.} =
  genInfo(pureNameId, qualname, docStr, fields, fields.len, doIt)

genInfo Version, "sys.version_info", """
sys.version_info

Version infomation as a named tuple.""", [
    ("major", "Major release number"),
    ("minor", "Minor release number"),
    ("micro", "Patch release number"),
    ("releaselevel", "'alpha', 'beta', 'candidate', or 'final'"),
    ("serial", "Serial release number"),
    ]:
  SetIntFlag PyMajor
  SetIntFlag PyMinor
  SetIntFlag PyPatch
  SetAscFlag PyReleaseLevelStr
  SetIntFlag PY_RELEASE_SERIAL


genInfo Float, "sys.float_info", """
sys.float_info

A named tuple holding information about the float type. It contains low level
information about the precision and internal representation. Please study
your system's :file:`float.h` for more information.""", [
    ("max",             "DBL_MAX -- maximum representable finite float"),
    ("max_exp",         "DBL_MAX_EXP -- maximum int e such that radix**(e-1) "&
                    "is representable"),
    ("max_10_exp",      "DBL_MAX_10_EXP -- maximum int e such that 10**e "&
                    "is representable"),
    ("min",             "DBL_MIN -- Minimum positive normalized float"),
    ("min_exp",         "DBL_MIN_EXP -- minimum int e such that radix**(e-1) "&
                    "is a normalized float"),
    ("min_10_exp",      "DBL_MIN_10_EXP -- minimum int e such that 10**e is "&
                    "a normalized float"),
    ("dig",             "DBL_DIG -- maximum number of decimal digits that "&
                    "can be faithfully represented in a float"),
    ("mant_dig",        "DBL_MANT_DIG -- mantissa digits"),
    ("epsilon",         "DBL_EPSILON -- Difference between 1 and the next "&
                    "representable float"),
    ("radix",           "FLT_RADIX -- radix of exponent"),
    ("rounds",          "FLT_ROUNDS -- rounding mode used for arithmetic "&
                    "operations"),
    ]:
  SetDblFlag(DBL_MAX)
  SetIntFlag(DBL_MAX_EXP)
  SetIntFlag(DBL_MAX_10_EXP)
  SetDblFlag(DBL_MIN)
  SetIntFlag(DBL_MIN_EXP)
  SetIntFlag(DBL_MIN_10_EXP)
  SetIntFlag(DBL_DIG)
  SetIntFlag(DBL_MANT_DIG)
  SetDblFlag(DBL_EPSILON)
  SetIntFlag(FLT_RADIX)
  SetIntFlag(FLT_ROUNDS)

genInfo Int, "sys.int_info", """
sys.int_info

A named tuple that holds information about Python's
internal representation of integers.  The attributes are read only.
""", [
  ("bits_per_digit", "size of a digit in bits"),
  ("sizeof_digit", "size in bytes of the C type used to represent a digit"),
  ("default_max_str_digits", "maximum string conversion digits limitation"),
  ("str_digits_check_threshold", "minimum positive value for int_max_str_digits"),
]:
  SetIntFlag digitBits
  SetIntFlag sizeof(Digit)
  SetIntFlag PY_INT_DEFAULT_MAX_STR_DIGITS
  SetIntFlag PY_INT_MAX_STR_DIGITS_THRESHOLD

genInfo Hash, "sys.hash_info", """
sys.hash_info

A named tuple providing parameters used for computing
hashes. The attributes are read only
""", [
    ("width", "width of the type used for hashing, in bits"),
    ("modulus", "prime number giving the modulus on which the hash)"&
                "function is based"),
    ("inf", "value to be used for hash of a positive infinity"),
    ("nan", "value to be used for hash of a nan"),
    ("imag", "multiplier used for the imaginary part of a complex number"),
    ("algorithm", "name of the algorithm for hashing of str, bytes and)"&
                  "memoryviews"),
    ("hash_bits", "internal output size of hash algorithm"),
    ("seed_bits", "seed size of hash algorithm"),
    ("cutoff", "small string optimization cutoff"),
]:
  let hashfunc = PyHash_GetFuncDef()
  SetIntFlag 8 * sizeof Hash
  SetIntFlag high Hash
  SetIntFlag pyhash.INF
  SetIntFlag 0  # This is no longer used
  SetIntFlag pyhash.IMAG
  SetAscFlag hashfunc.name
  SetIntFlag hashfunc.hash_bits
  SetIntFlag hashfunc.seed_bits
  SetIntFlag 0
