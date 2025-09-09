## workaround, currently assume only one `sys.modules` exists

import ../Objects/dictobject

var sys* = (modules: newPyDict())
