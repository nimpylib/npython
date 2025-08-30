const SingleThread* = defined(js) or not compileOption"threads"
when SingleThread:
  template orSingleThrd(body, js): untyped = js
else:
  template orSingleThrd(body, js): untyped = body

{.push inline.}
proc Py_atomic_compare_exchange*[T: AtomType](obj, expected: ptr T, desired: T): bool =
  orSingleThrd:
    atomicCompareExchangeN(obj, expected, desired, false, ATOMIC_SEQ_CST, ATOMIC_SEQ_CST)
  do:
    result = obj[] == expected[]
    if result:
      obj[] = desired
    else:
      expected[] = obj[]

proc Py_atomic_load*[T: AtomType](obj: ptr T): T =
  orSingleThrd:
    atomicLoadN(obj, ATOMIC_SEQ_CST)
  do: obj[]

template genLoadStore(atomicOpKind){.dirty.} =
  proc `Py_atomic_load atomicOpKind`*[T: AtomType and not SomeFloat](obj: ptr T): T =
    orSingleThrd:
      atomicLoadN(obj, `ATOMIC atomicOpKind`)
    do: obj[]
  proc `Py_atomic_load atomicOpKind`*[T: ref](obj: ptr T): T = cast[T](`Py_atomic_load atomicOpKind`(cast[ptr pointer](obj)))
  # XXX: float,double cannt use atomicStoreN and atomicLoadN, or CC will error
  proc `Py_atomic_load atomicOpKind`*[T: SomeFloat](obj: ptr T): T =
    orSingleThrd:
      atomicLoad(cast[ptr T](obj), result.addr, `ATOMIC atomicOpKind`)
    do: result = obj[]

  proc `Py_atomic_store atomicOpKind`*[T: AtomType and not SomeFloat](obj: ptr T, value: T) =
    orSingleThrd:
      atomicStoreN(obj, value, `ATOMIC atomicOpKind`)
    do: obj[] = value
  proc `Py_atomic_store atomicOpKind`*[T: ref](obj: ptr T, value: T) = `Py_atomic_store atomicOpKind`(cast[ptr pointer](obj), value)
  proc `Py_atomic_store atomicOpKind`*[T: SomeFloat](obj: ptr T, value: T) =
    orSingleThrd:
      atomicStore(obj, value.addr, `ATOMIC atomicOpKind`)
    do: obj[] = value
genLoadStore RELAXED
genLoadStore SEQ_CST
{.pop.}
template genDefOp(atomicOpKind){.dirty.} =
  template `Py_atomic_load`*[T: AtomType and not SomeFloat](obj: ptr T): T = `Py_atomic_load atomicOpKind`(obj)
  template `Py_atomic_load`*[T: ref](obj: ptr T): T = `Py_atomic_load atomicOpKind`(obj)
  template `Py_atomic_load`*[T: SomeFloat](obj: ptr T): T = `Py_atomic_load atomicOpKind`(obj)
  template `Py_atomic_store`*[T: AtomType and not SomeFloat](obj: ptr T, value: T) = `Py_atomic_store atomicOpKind`(obj, value)
  template `Py_atomic_store`*[T: ref](obj: ptr T, value: T) = `Py_atomic_store atomicOpKind`(obj, value)
  template `Py_atomic_store`*[T: SomeFloat](obj: ptr T, value: T) = `Py_atomic_store atomicOpKind`(obj, value)
genDefOp SEQ_CST
