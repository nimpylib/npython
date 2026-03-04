## `pycore_long.h`
import pkg/intobject/Include/pycore_int
export pycore_int except get_intobject_state

template PyInterpreterState_GET_long_state*(): untyped =
  ## `_PyInterpreterState_GET->long_state`
  bind get_intobject_state
  get_intobject_state()
