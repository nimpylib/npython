
template withNoRecusiveCallOrRetE*(where: cstring; body) = body
  #TODO:rec
#[
  bind Py_EnterRecursiveCall, Py_LeaveRecursiveCall, retIfExc
  retIfExc Py_EnterRecursiveCall(where)
  defer: Py_LeaveRecursiveCall()
  body
]#