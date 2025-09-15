
template withNoRecusiveCallOrRetE*(where: cstring; body) = body
  #TODO:rec
#[
  bind Py_EnterRecursiveCall, Py_LeaveRecursiveCall, retIfExc
  retIfExc Py_EnterRecursiveCall(where)
  body
  Py_LeaveRecursiveCall()
]#