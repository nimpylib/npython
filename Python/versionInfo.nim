
const
  Major* = 0
  Minor* = 1
  Patch* = 1

  PyMajor*{.intdefine.} = 3
  PyMinor*{.intdefine.} = 13
  PyPatch*{.intdefine.} = 0

  PyReleaseLevel*{.intdefine.} = 0xA
  PyReleaseLevelStr*{.strdefine.} = "alpha"
  PY_RELEASE_SERIAL*{.intdefine.} = 0

const sep = '.'
template asVersion(major, minor, patch: int): string =
  $major & sep & $minor & sep & $patch

const
  Version* = asVersion(Major, Minor, Patch)
