{.used.}
import ./[
  pyobject,
  stringobject,
  exceptions,
  iterobject,
]
import ./abstract/sequence


methodMacroTmpl SeqIter

implSeqIterMagic iternext:
  #{.push warning[OverflowCheck]: off.}
  let sequ = self.sequ
  if sequ.isNil: return newStopIterError()

  if self.idx == high int:
    return newOverflowError newPyAscii"iter index too large"
  result = PySequence_GetItemNonNil(sequ, self.idx)
  if not result.isThrownException:
    self.idx.inc
    return
  if result.ofPyIndexErrorObject or result.isExceptionOf(StopIter):
    self.sequ = nil
  #{.pop.}

