import pyobject
import exceptions
import ../Include/cpython/pyerrors
import ./abstract/sequence
import ./stringobject


declarePyType NimSeqIter():
    items: seq[PyObject]
    idx: int

implNimSeqIterMagic iter:
  self

template stopIter =
  return newStopIterError()

implNimSeqIterMagic iternext:
  if self.idx == self.items.len: stopIter
  result = self.items[self.idx]
  inc self.idx

proc newPySeqIter*(items: seq[PyObject]): PyNimSeqIterObject = 
  result = newPyNimSeqIterSimple()
  result.items = items


declarePyType SeqIter():
    sequ: PyObject
    idx: int

implSeqIterMagic iter: self

implSeqIterMagic iternext:
  #{.push warning[OverflowCheck]: off.}
  let sequ = self.sequ
  if sequ.isNil: stopIter

  if self.idx == high int:
    return newOverflowError newPyAscii"iter index too large"
  result = PySequence_GetItemNonNil(sequ, self.idx)
  if not result.isThrownException:
    self.idx.inc
    return
  if result.ofPyIndexErrorObject or result.isExceptionOf(StopIter):
    self.sequ = nil
  #{.pop.}

proc newPySeqIter*(sequ: PyObject; exc: var PyBaseErrorObject): PySeqIterObject =
  result = newPySeqIterSimple()
  if not PySequence_Check(sequ):
    exc = PyErr_BadInternalCall()
    return
  result.idx = 0
  result.sequ = sequ

proc newPySeqIter*(sequ: PyObject): PyObject =
  var exc: PyBaseErrorObject
  result = newPySeqIter(sequ, exc)
  if result.isNil: result = exc

template pyForIn*(it; iterableToLoop: PyObject; doWithIt) =
  ## pesudo code: `for it in iterableToLoop: doWithIt`
  ##   but `return` PyBaseErrorObject if python's exception is raised
  let (iterable, nextMethod) = getIterableWithCheck(iterableToLoop)
  if iterable.isThrownException:
    return PyBaseErrorObject iterable
  while true:
    let it = nextMethod(iterable)
    if it.isStopIter:
      break
    if it.isThrownException:
      return PyBaseErrorObject it
    doWithIt


type ItorPy = iterator(): PyObject{.raises: [].}
declarePyType NimIteratorIter():
  itor: ItorPy

implNimIteratorIterMagic iter:
  self

implNimIteratorIterMagic iternext:
  result = self.itor()
  if self.itor.finished():
    return newStopIterError()

proc newPyNimIteratorIter*(itor: ItorPy): PyNimIteratorIterObject = 
  result = newPyNimIteratorIterSimple()
  result.itor = itor

template genPyNimIteratorIter*(iterable): PyNimIteratorIterObject =
  bind newPyNimIteratorIter
  newPyNimIteratorIter iterator(): PyObject =
    for i in iterable: yield i
