

template orRetValOrOvfErr*(pyexp): untyped =
    try: pyexp
    except ValueError as e: return newValueError newPyAscii e.msg
    except OverflowDefect as e: return newOverflowError newPyAscii e.msg

