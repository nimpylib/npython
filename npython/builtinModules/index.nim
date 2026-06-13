
import std/macros
import std/os
import ../Python/sysmodule_instance
import ../Objects/[
  pyobject,
  moduleobject,
  dictobject,
  listobject,
]

#const moduleIds = CacheSeq"npyBuiltinModulesCache"
var moduleIds{.compileTime.}: seq[string]

template toInit(id): NimNode =
  ident("PyInit_" & id.strVal)

proc reg_builtin_moduleImpl(
    #modules: PyDictObject, builtin_module_names: PyListObject; modu) =
    modules, builtin_module_names, modu: NimNode): NimNode =
  let init = modu.toInit
  result = quote do:
    block:
      let modObj = `init`() #`modu`.make_module()
      #TODO:import
      assert modObj.ofPyModuleObject
      let moduO = PyModuleObject modObj
      let moduS = moduO.name
      `modules`[moduS] = moduO
      `builtin_module_names`.add(moduS)

template get_modules:  NimNode = newDotExpr(bindSym"sys", ident"modules")
template get_bltnames: NimNode = newDotExpr(bindSym"sys", ident"builtin_module_names")

template reg_builtin_module*(modu) =
  ## like `PyImport_AppendInittab`
  reg_builtin_moduleImpl(get_modules(), get_bltnames(), modu)

static:
  for (k, i) in walkDir(currentSourcePath().parentDir, relative=true):
    if k == pcDir: continue
    if i == "index.nim": continue
    moduleIds.add i[0..^5]

macro init_builtin_modules_table_pre =
  result = newStmtList()
  for i in moduleIds:
    let id = ident i
    let init = id.toInit
    result.add quote do:
      from ./`id` import `init`
      export `init`

init_builtin_modules_table_pre()

macro add_builtin_modules* =
  result = newStmtList()
  let
    sys_module = get_modules()
    builtin_module_names = get_bltnames()

  for i in moduleIds:
    result.add reg_builtin_moduleImpl(
      sys_module, builtin_module_names,
      ident i  # remove .nim
    )
