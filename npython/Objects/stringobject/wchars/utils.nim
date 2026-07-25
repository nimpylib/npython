
import std/macros
macro npyexportcNoJs*(name: static[string], def) =
  ## BYPASS(NIM-BUG):
  ## Error: unhandled exception: index 7 not in 0 .. 6 [IndexDefect]
  ## in genProc of jsgen.nim
  result = def
  when not defined(jspure):
    def.addPragma nnkExprColonExpr.newTree(
      ident"npyexportc", newLit name
    )

