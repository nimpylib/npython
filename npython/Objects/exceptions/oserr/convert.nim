
#TODO:oserr
#import pkg/posixos

template handleOsErrRetPyObj*(body): untyped =
  try:
    body
  except OSError as e:
    return newOSError newPyAscii e.msg
