## just placeholder, as npython doesn't have GIL

type PyGILState_STATE* = ref object

var state{.threadVar.}: PyGILState_STATE
proc PyGILState_Ensure*: PyGILState_STATE =
  once: new state
  state


proc PyGILState_Release*(state: PyGILState_STATE) = discard

template withPyGIL*(body) =
  let st = PyGILState_Ensure()
  defer: PyGILState_Release st
  body

