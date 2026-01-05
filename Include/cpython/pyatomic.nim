
template FT*(x): untyped = addr x  ## for FT_xxxx

const SingleThread* = defined(js) or not compileOption"threads"
when SingleThread:
  template orSingleThrd(body, js): untyped = js
else:
  when not declared(atomicLoad):
    import ./pyatomic_std
    const FltNotAtomic = false
  else:
    # XXX: float,double cannot use atomicStoreN and atomicLoadN
    # (`__atomic_store_n` and `__atomic_load_n`), or GCC will error
    const FltNotAtomic = true
  
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


template genLoadStore(atomicOpKind){.dirty.} =
  proc `Py_atomic_load atomicOpKind`*[T: AtomType|SomeFloat](obj: ptr T): T =
    orSingleThrd:
      when T is SomeFloat and FltNotAtomic:
        atomicLoad(cast[ptr T](obj), result.addr, `ATOMIC atomicOpKind`)
      else:
        result = atomicLoadN(obj, `ATOMIC atomicOpKind`)
    do: result = obj[]
  proc `Py_atomic_load atomicOpKind`*[T: ref](obj: ptr T): T = cast[T](`Py_atomic_load atomicOpKind`(cast[ptr pointer](obj)))

  proc `Py_atomic_store atomicOpKind`*[T: AtomType|SomeFloat](obj: ptr T, value: T) =
    orSingleThrd:
      when T is SomeFloat and FltNotAtomic:
        atomicStore(obj, value.addr, `ATOMIC atomicOpKind`)
      else:
        atomicStoreN(obj, value, `ATOMIC atomicOpKind`)
    do: obj[] = value
  proc `Py_atomic_store atomicOpKind`*[T: ref](obj: ptr T, value: T) = `Py_atomic_store atomicOpKind`(cast[ptr pointer](obj), value)
genLoadStore RELAXED
genLoadStore SEQ_CST
{.pop.}
template genDefOp(atomicOpKind){.dirty.} =
  template `Py_atomic_load`*[T: AtomType|SomeFloat|ref](obj: ptr T): T = `Py_atomic_load atomicOpKind`(obj)
  template `Py_atomic_store`*[T: AtomType|SomeFloat|ref](obj: ptr T, value: T) = `Py_atomic_store atomicOpKind`(obj, value)
genDefOp SEQ_CST
