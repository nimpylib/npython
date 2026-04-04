## atomic operations of c11/c++11 
# assuming no `__STD_NO_ATOMIC__`

const
  ATOMIC_RELAXED* = 0.AtomMemModel
  ATOMIC_CONSUME* = 1.AtomMemModel
  ATOMIC_ACQUIRE* = 2.AtomMemModel
  ATOMIC_RELEASE* = 3.AtomMemModel
  ATOMIC_ACQ_REL* = 4.AtomMemModel
  ATOMIC_SEQ_CST* = 5.AtomMemModel

when defined(cpp):
  {.push header: "<atomic>".}
  type Atomic[T]{.importc: "std::atomic".} = object

  proc atomic_load_explicit[T](obj: ptr Atomic[T], mem: AtomMemModel): T {.importc: "std::atomic_load_explicit".}
  proc atomic_store_explicit[T](obj: ptr Atomic[T], val: T, mem: AtomMemModel) {.importc: "std::atomic_store_explicit".}
else:
  {.push header: "<stdatomic.h>".}
  type Atomic[T] {.importcpp: "_Atomic('0)".} = object
  proc atomic_load_explicit[T](obj: ptr Atomic[T], mem: AtomMemModel): T {.importc.}
  proc atomic_store_explicit[T](obj: ptr Atomic[T], val: T, mem: AtomMemModel) {.importc.}

{.pop.}

proc atomicLoadN*[T](obj: ptr T, mem: AtomMemModel): T =
  atomic_load_explicit(cast[ptr Atomic[T]](obj), mem)

proc atomicStoreN*[T](obj: ptr T, val: T, mem: AtomMemModel) =
  atomic_store_explicit(cast[ptr Atomic[T]](obj), val, mem)


