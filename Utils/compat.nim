# from ./utils import InterruptError
#  currently uses EOFError
when defined(js):
  import std/jsconsole
  const
    karax* = defined(karax)
    jsAlert = defined(jsAlert)
  when jsAlert:
    proc alert(s: cstring){.importc.}
    template errEchoCompat*(content: string) =
      let cs = cstring content
      console.error cs
      alert cs
    template echoCompat*(content: string) =
      alert cstring content
  elif karax:
    include karax/prelude
    var stream*: seq[(kstring, kstring)]
    template echoCompat*(content: string) =
      echo content
      stream.add((kstring"", kstring(content)))
    template errEchoCompat*(content: string) =
      echoCompat content
  else:
    template echoCompat*(content: string) =
      echo content
    template errEchoCompat*(content: string) =
      console.error cstring content

  import std/jsffi

  when defined(nodejs):

    type
      InterfaceConstructor = JsObject
      InterfaceConstructorWrapper = object
        obj: InterfaceConstructor
      Promise[T] = JsObject
    template wrapPromise[T](x: T): Promise[T] = cast[Promise[T]](x) ## \
    ## async's result will be wrapped by JS as Promise'
    ## this is just to bypass Nim's type system
    import std/macros
    macro async(def): untyped =
      var origType = def.params[0]
      let none = origType.kind == nnkEmpty
      if none: origType = bindSym"void"

      def.params[0] = nnkBracketExpr.newTree(bindSym"Promise", origType)
      if def.kind in RoutineNodes:
        def.addPragma nnkExprColonExpr.newTree(
            ident"codegenDecl",
            newLit"async function $2($3)"
        )
        if not none:
          def.body = newCall(bindSym"wrapPromise", def.body)
      def

    #template await*[T](exp: Promise[T]): T = {.emit: ["await ", exp].}

    ## XXX: top level await, cannot be in functions
    template waitFor[T](exp: Promise[T]): T =
      let e = exp
      var t: T
      {.emit: [t, " = await ", e].}
      # " <- for code hint
      t
    template waitFor(exp: Promise[void]) =
      let e = exp
      {.emit: ["await ", e].}
    
    template await[T](exp: Promise[T]): T =
      waitFor exp

    {.emit: """/*INCLUDESECTION*/
     import {createInterface}  from 'node:readline/promises';
     import { stdin as input, stdout as output } from 'node:process';
     """.} # """ <- for code hint
    proc initReadLine: InterfaceConstructorWrapper =
      {.emit: """
      // top level await must be on ES module
      //const { createInterface } = require('node:readline');
      //const { stdin: input, stdout: output } = require('node:process');

      const rl = createInterface({ input, output });
      rl.on("SIGINT", ()=>{});
      // XXX: TODO: correctly handle ctrl-c (SIGINT)
      """.}
      # Python does not exit on ctrl-c
      # but re-asking a new input
      #  I'd tried to implement that but failed,
      #  current impl of handler is just doing nothing (an empty function)
      {.emit: [result.obj, "= rl;"].}
    when defined(nimPreviewNonVarDestructor):
      proc `=destroy`(o: InterfaceConstructorWrapper) = o.obj.close()
    else:
      proc `=destroy`(o: var InterfaceConstructorWrapper) = o.obj.close()

    proc cursorToNewLine{.noconv.} =
      console.log(cstring"")
    let rl = initReadLine()
    proc question(rl: InterfaceConstructor, ps: cstring): Promise[cstring]{.importcpp.}
    proc questionHandledEof(rl: InterfaceConstructor, ps: cstring
    ): Promise[cstring] =
      ## rl.question(ps) but catch EOF and raise as EOFError
      {.emit: [
        result, " = ",
        rl, ".question(", ps, """).catch(e=>{
          if (typeof(e) === "object" && e.code === "ABORT_ERR") {""",
            r"return '\0';",
          """
          }
        });"""
        # """ <- for code hint
      ].}

    
    proc readLineCompat*(ps: cstring): cstring{.async.} =
      let res = await rl.obj.questionHandledEof ps
      if res == cstring("\0"):
        cursorToNewLine()
        raise new EOFError
      res
    proc readLineCompat*(prompt: string): string{.async.} =
      $(await prompt.cstring.readLineCompat)

    template mayAsync*(def): untyped =
      bind async
      async(def)
    template mayAwait*(x): untyped =
      bind await
      await x
    template mayWaitFor*(x): untyped =
      ## top level await
      bind waitFor
      waitFor x

  else:
    import std/jsffi
    proc readLineCompat*(prompt: cstring): JsObject#[cstring or null]#{.importc: "prompt".}

    proc readLineCompat*(prompt: string): string =
      let res = prompt.cstring.readLineCompat
      if res.isNull:
        raise new EOFError
      $(res.to(cstring))
    when defined(deno):
      proc cwd(): cstring{.importc: "Deno.cwd".}
      proc getCurrentDir*(): string = $cwd()
      proc quitCompat*(e=0){.importc: "Deno.exit".}
      proc quitCompat*(e: string) =
        bind errEchoCompat, quitCompat
        errEchoCompat(e)
        quitCompat QuitFailure

  # Years ago...
  # combining two seq directly leaded to a bug in the compiler when compiled to JS
  # see gh-10651 (have been closed)
  template addCompat*[T](a, b: seq[T]) = 
    a.add b

else:
  import rdstdin


  template readLineCompat*(prompt): string = 
    readLineFromStdin(prompt)

  template echoCompat*(content) = 
    echo content

  template errEchoCompat*(content) = 
    stderr.writeLine content

  template addCompat*[T](a, b: seq[T]) = 
    a.add b
    
when not declared(async):
  template mayAsync*(def): untyped = def
  template mayAwait*(x): untyped = x
  template mayWaitFor*(x): untyped = x

when not declared(getCurrentDir):
  import std/os
  export getCurrentDir

when not declared(quitCompat):
  template quitCompat*(e: untyped = 0) = quit(e)
