import pyobject
import exceptions


declarePyType SeqIter():
    items: seq[PyObject]
    idx: int

implSeqIterMagic iter:
  self

implSeqIterMagic iternext:
  if self.idx == self.items.len:
    return newStopIterError()
  result = self.items[self.idx]
  inc self.idx

proc newPySeqIter*(items: seq[PyObject]): PySeqIterObject = 
  result = newPySeqIterSimple()
  result.items = items

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
