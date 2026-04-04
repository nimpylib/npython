
import ../../Include/internal/pycore_ceval_rec
import ../../Include/ceval
import ../../Utils/fileio
import ../../Utils/[intflags,]
export intflags
import ../[
  pyobjectBase,
  exceptions,
  stringobject,
]
import ../exceptions/ioerror
import ./strings


# Flag bits for printing:
declareIntFlag PyPrintFlags:
  Py_PRINT_REPR = 0
  Py_PRINT_RAW = 1   ## No string quotes etc. (using str over repr)

template PyObject_WriteImpl(writePrc) =
  ## variant of PyObject_Print that also appends an '\n'
  #TODO:PyErr_CheckSignals
  when declared(PyErr_CheckSignals):
    retIfExc PyErr_CheckSignals()  #TODO:signal
  withNoRecusiveCallOrRetE " printing an object":
    #clearerr(fp)
    template writeImpl =
      let s = if flags & Py_PRINT_RAW:
        PyObject_StrNonNil(op)
      else:
        PyObject_ReprNonNil(op)
      retIfExc s
      assert s.ofPyStrObject
      let t = PyStrObject(s).asUTF8()
      writePrc fp, t
    try:
      if op.isNiL:
        pyAllowThreads:
          writePrc fp, "<nil>"
      else:
        when compiles(Py_REFCNT(op)):
          let cnt = Py_REFCNT(op)
          if cnt <= 0:
            pyAllowThreads:
              writePrc fp, "<refcnt " & $cnt & " at " & repr p & ">"
          else: writeImpl
        else: writeImpl
    except IOError as e:
      result = newIOError e #TODO:OSError PyErr_SetFromErrno(pyOSErrorObjectType)
      #clearerr(fp)

proc PyObject_Println*(op: PyObject, fp: fileio.File, flags: IntFlag[PyPrintFlags] = Py_PRINT_REPR): PyBaseErrorObject =
  ## variant of PyObject_Print that also appends an '\n'
  PyObject_WriteImpl writeLine
