
import std/macros
import std/os
import std/tables
when defined(js):
  import std/sets
  from std/strutils import splitLines
import ../Python/sysmodule_instance
import ../Objects/[
  pyobject,
  moduleobject,
  dictobject,
  stringobject,
  listobject,
]

#const moduleIds = CacheSeq"npyBuiltinModulesCache"
var moduleIds{.compileTime.}: seq[string]

template toInit(id): NimNode =
  ident("PyInit_" & id.strVal)
template toName(id): NimNode =
  ident(id.strVal & "ModuleName")

var tab: Table[string, proc (): PyObject{.raises: [].}]

template withBuiltinModule*(name: string; value; body) =
  ## internal use only, for builtin modules. like `math`, `pwd`, etc.
  bind tab, withValue
  withValue tab, name, value:
    body

proc reg_builtin_moduleImpl(
    #modules: PyDictObject, builtin_module_names: PyListObject; modu) =
    builtin_module_names, modu: NimNode): NimNode =
  let init = modu.toInit
  let moduName = modu.toName
  let tabId = bindSym"tab"
  let str = bindSym"newPyAscii"
  result = quote do:
    block:
      let moduS = `moduName`
      `tabId`[moduS] = `init`
      `builtin_module_names`.add(`str` moduS)

#template get_modules:  NimNode = newDotExpr(bindSym"sys", ident"modules")
template get_bltnames: NimNode = newDotExpr(bindSym"sys", ident"builtin_module_names")

template reg_builtin_module*(modu) =
  ## like `PyImport_AppendInittab`
  reg_builtin_moduleImpl(get_bltnames(), modu)

when defined(js):
  import ./private/skipHandleUtil
else:
  template skipHandled(modname, body) {.dirty.} = body
static:
  const dir = currentSourcePath().parentDir
  for (k, i) in walkDir(dir, relative=true):
    if k == pcDir: continue
    if i == "index.nim": continue
    let pureName = i[0..^5]
    skipHandled pureName:
      moduleIds.add pureName

macro init_builtin_modules_table_pre =
  result = newStmtList()
  for i in moduleIds:
    let id = ident i
    let init = id.toInit
    let moduName = id.toName
    result.add quote do:
      from ./`id` import `init`, `moduName`
      export `init`, `moduName`

init_builtin_modules_table_pre()

macro add_builtin_modules* =
  result = newStmtList()
  let
    builtin_module_names = get_bltnames()

  for i in moduleIds:
    result.add reg_builtin_moduleImpl(
      builtin_module_names,
      ident i  # remove .nim
    )
