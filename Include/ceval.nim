
import ./internal/[
  defines_gil, #pycore_pystate,  #TODO:tstate
]


when SingleThread:
  template pyAllowThreads*(body) = body
else:
  template pyAllowThreads*(body) =
    #Py_BEGIN_ALLOW_THREADS
    body
    #Py_END_ALLOW_THREADS

