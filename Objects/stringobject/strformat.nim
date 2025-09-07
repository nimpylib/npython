## for PyObject being working with std/strformat
import std/strformat
export strformat
include ./common_h
when defined(nimdoc):
  # for runnableExample
  export stringobject
import ../typeobject/getters
import ../pyobject_apis/strings
import ../../Utils/utils

type FormatPyObjectError = object of CatchableError

var exc: PyBaseErrorObject

template handleFormatExc*(handle, body) =
  bind exc, FormatPyObjectError
  try: body
  except FormatPyObjectError: handle exc

template ret(e) = return e
template handleFormatExc*(body) = handleFormatExc(ret, body)


template gen(TspecS; ct: bool, invalid_format){.dirty.} =
  proc formatValue*[O: PyObject](s: var string, obj: O, specS: TspecS){.raises: [FormatPyObjectError].} =
    ## remember to wrap around `handleFormatExc`
    template raisePyExcAsNim[E: PyBaseErrorObject](e: E) =
      exc = e
      raise new FormatPyObjectError
    template notImpl(s) = raisePyExcAsNim newNotImplementedError newPyAscii s
    when ct:
      const nspecS = specS[0..<specS.high]
    else:
      var nspecS = specS
      nspecS[^1] = 's'
    template sadd(o: PyStrObject) =
      # XXX: as we've `parseStandardFormatSpecifier specS`,
      #  so the spec string shall be in good format here.
      ValueError!!s.formatValue($o.str, nspecS)
    template sadd(o: PyObject) =
      # XXX: as we've `parseStandardFormatSpecifier specS`,
      #  so the spec string shall be in good format here.
      sadd PyStrObject o
    template raiseIfExc(o: PyObject) =
      if o.isThrownException:
        raisePyExcAsNim PyBaseErrorObject o
    template saddType(typ: PyTypeObject) =
      let type_name = if spec.alternateForm: getFullyQualifiedName(typ, ':')
      else: getFullyQualifiedName(typ)
      raiseIfExc type_name
      sadd type_name
    template doWith(op) =
      assert not obj.isNil
      let repr = op(obj)
      raiseIfExc repr
      sadd repr
    let spec = try: parseStandardFormatSpecifier specS
    except ValueError: invalid_format specS
    case spec.typ
    of 'R', '\0': doWith PyObject_ReprNonNil
    of 'S': doWith PyObject_StrNonNil
    of 'U': sadd obj
    of 'A': notImpl "NPython: %A not impl yet"  #TODO:ascii
    of 'T':
      let typ = obj.pyType
      saddType typ
    of 'N':
      var typ: PyTypeObject
      if not obj.ofPyTypeObject:
        raisePyExcAsNim newTypeError newPyAscii"%N argument must be a type"
      saddType typ
    else:
      invalid_format specS

template invalid_format(specS) = raisePyExcAsNim newSystemError newPyStr fmt"invalid format string: {specS}"
gen string, false, invalid_format
template invalid_format_ct(specS) = raise newException(FormatPyObjectError, fmt"invalid format string: {specS}")
gen static[string], true, invalid_format_ct


template `&`*(fun; str: string{lit}): PyObject =
  ## PyUnicode_FromFormat <- newPyStr&"xxx {v:spec} xxx"
  ## 
  ## XXX: we use `&` to cheat LSP to work (for syntax highlight)
  runnableExamples:
    let a = newPyAscii"e"
    echo newPyStr&"abc {a}"
  bind exc, fmt, FormatPyObjectError
  var s: string
  try:
    s = fmt str
    fun s
  except FormatPyObjectError: exc

