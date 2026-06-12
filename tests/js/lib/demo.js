
import {Py_Initialize, Py_Finalize,
  PyRun_SimpleString, PyRun_String,
  PyImport_AddModuleRef, PyModule_GetDict,
  PyObject_Repr,
  PyUnicode_AsUTF8StringSafe, PyBytes_AsString,
} from "../../../bin/npython.lib.js"

Py_Initialize()
//PyRun_SimpleString("print(1)")

// get `globals()`
let main = PyImport_AddModuleRef("__main__")
let globals = PyModule_GetDict(main)

let res = PyRun_String("999+1", 2, globals, globals)

// `res` to js String
let pystr = PyObject_Repr(res)
let pybytes = PyUnicode_AsUTF8StringSafe(pystr)
let s = PyBytes_AsString(pybytes)

console.assert(s === "1000")

Py_Finalize()
