
const
  Major* = 0
  Minor* = 1
  Patch* = 1

const sep = '.'
template asVersion(major, minor, patch: int): string =
  $major & sep & $minor & sep & $patch

const
  Version* = asVersion(Major, Minor, Patch)
