
const Js = defined(js)
when Js:
  when defined(nodejs):
    proc abort*(){.noReturn, importc: "process.abort()".}
  elif defined(deno):
    proc abort*(){.noReturn, importc: "Deno.abort()".}
  else:
    proc abort*(){.noReturn, importc: """(
      process?process.abort():(
      Deno?Deno.abort():(
        window.abort()
      ))
    )""".}
else:
  proc abort*(){.noReturn, importc, header: "<stdlib.h>".}

when defined(windows):
  proc DebugBreak*(){.imporc, header: "<debugapi.h>".}
