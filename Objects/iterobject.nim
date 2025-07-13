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
  let (iterable, nextMethod) = getIterableWithCheck(iterableToLoop)
  if iterable.isThrownException:
    return iterable
  while true:
    let it = nextMethod(iterable)
    if it.isStopIter:
      break
    if it.isThrownException:
      return it
    doWithIt
