
import std/macros
macro genModuleType*(module; types: static openArray[string]) =
  let ls = newStmtList()
  let PyT = ident"PyObject"
  for i in types:
    let p = ident i
    ls.add newCall(
      quote do: `p`{.member.}
      ,
      newStmtList PyT
    )

  let
    moduleS = module.strVal
    moduleName = moduleS & "Module"
    moduleT = ident moduleName
  result = newStmtList nnkCommand.newTree(ident"declarePyType",
    quote do: `moduleT`(base(Module))
    ,
    ls
  )

macro initTypes*(modu: typed; types: static openArray[string]) =
  result = newStmtList()
  for i in types:
    let p = ident i
    let typ = ident "py" & i & "ObjectType"
    result.add quote do:
      `modu`.`p` = `typ`

template genInit*(module; types: static openArray[string]) =
  bind initTypes
  const `module ModuleName`* = astToStr(module)

  proc `PyInit module`*: PyObject =
    result = PyModule_CreateInitialized(`module`)
    retIfExc result
    let modu = `Py module ModuleObject` result
    modu.initTypes types

template genModuleWithTypes*(module; types: static openArray[string]) =
  genModuleType module, types
  genInit module, types

template genModule*(module) = genModuleWithTypes module, []


