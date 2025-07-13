

const canCTCompileAndRe2 = defined(npythonUseRegex)

const npythonUseRe{.booldefine.} = true

template declCapturedStr(ret){.dirty.} =
  template capturedStr*(r: RegexMatch, line: string): string = ret

when canCTCompileAndRe2:
  import regex
  type RegexMatch* = regex.RegexMatch2
  export regex.find
  declCapturedStr line[r.boundaries]

elif npythonUseRe:
  import std/re

  type RegexMatch* = Slice[int]
  template boundaries*(r: RegexMatch): untyped = r
  declCapturedStr line[r]
  proc find*(buf: string, pattern: Regex, match: var RegexMatch, start=0): bool{.inline.} =
    (match.a, match.b) = findBounds(buf, pattern, start)# != (-1,0)
    match.a != -1

elif defined(npythonUseNre):
  import std/nre
  import ../Utils/utils
  export RegexMatch
  template boundaries*(r: RegexMatch): untyped = r.captureBounds[-1]
  declCapturedStr r.captures[-1]
  proc find*(buf: string, pattern: Regex, match: var RegexMatch, start=0): bool{.inline.} =
    let opt = try:
      buf.find(pattern, start)
    except ValueError: unreachable()
    # the `ValueError` is from: find <- matchImpl <- captureCount <- getinfo <- strutils.`%`
    #  but as the format string is static and you can tell it never ValueError
    except InvalidUnicodeError, RegexInternalError:
      # on returning false, the callee will raiseSyntaxError
      raise newException(InternalError, "std/nre.find: InvalidUnicode or RegexInternal")
    result = opt.isSome()
    if result:
      match = opt.unsafeGet()

when canCTCompileAndRe2:
  template compileLiteralRe*(name; str) =
    bind re2
    const name = re2(str)
else:
  template compileLiteralRe*(name; str) =
    # std/re, std/nre can't compile at compile-time
    bind re
    let name = re(str)
