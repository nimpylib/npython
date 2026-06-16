

template checkFlags*(flags; thenbody) =
  if flags.ord != ord PyBUF.SIMPLE:  # fast path
    if flags.ord == PyBUF.READ.ord or flags.ord == PyBUF.WRITE.ord:
      return PyErr_BadInternalCall()
    thenbody

