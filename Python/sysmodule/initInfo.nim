
import ./[
  initUtils, infos,
]

import ../../Objects/[
  dictobject,
  tupleobjectImpl,
  boolobject,
  structseq,
  namespaceobject,
]
import ../../Python/[
  getversion, modsupport, getcopyright,
]
import ../../Utils/getplatform
import ../../Include/[
  modsupport,
]
import ../../Modules/[
  getbuildinfo,
]

# sys.implementation values
const
  NAME = "npython"
  PySys_ImplName = NAME
  PySys_ImplCacheTag = NAME & '-' & $PyMajor & $PyMinor

proc make_impl_info(version_info: PyObject): PyObject =
  let impl_info = newPyDict()

  # populate the dict
  template SetA(name, val) =
    impl_info[newPyAscii name] = val
  template SetAA(name, val) =
    SetA name, newPyAscii val


  SetAA "name", PySys_ImplName
  SetAA "cache_tag", PySys_ImplCacheTag
  SetA  "version", version_info

  SetA  "hexversion", newPyInt PY_VERSION_HEX

  #[
#ifdef MULTIARCH
  SetA  "_multiarch" newPyStr MULTIARCH
#endif
]#
  # PEP-734
  # It is not enabled on WASM builds just yet
  let notV = defined(wasi) or defined(emscripten)
  SetA "supports_isolated_interpreters", newPyBool(not notV)

  newPyNamespace(impl_info)

template ensureInfoType(TYPE, DESC, flag): PyBaseErrorObject =
  PyStructSequence_InitBuiltinWithFlags(
    interp, TYPE, DESC, flag)
template ENSURE_INFO_TYPE(TYPE, DESC) =
  retIfExc ensureInfoType(TYPE, DESC, Py_TPFLAGS_DISALLOW_INSTANTIATION)


template Py_Int_Float_InitTypes*(fatalCb) =
  ## `_PyLong_InitTypes` and `_PyFloat_InitTypes`
  #XXX: CPython init following two in `pycore_init_types`
  bind ensureInfoType, FloatInfoType, FloatInfodesc, IntInfoType, IntInfodesc
  template pylifecycleInitType(TYPE, DESC, msg) =
    if not ensureInfoType(TYPE, DESC, Py_TPFLAGS_DISALLOW_INSTANTIATION).isNil:
      fatalCb msg
  pylifecycleInitType(FloatInfoType, Float_info_desc, "can't init float info type")
  pylifecycleInitType(IntInfoType, Int_info_desc, "can't init int info type")

proc initCore*(sysdict: PyDictObject): PyBaseErrorObject =
  ## `_PySys_InitCore`
  block:
    template COPY_SYS_ATTR(tokey, fromkey) =
      SET_SYS(tokey, sysdict.getItem(fromkey))
    template COPY_SYS_ATTR(key) =
      when declared(key):
        let ks = astToStr(key)
        COPY_SYS_ATTR("__"&ks&"__", ks)
    #TODO:sys.displayhook,...
    COPY_SYS_ATTR displayhook
    COPY_SYS_ATTR excepthook
    COPY_SYS_ATTR breakpointhook
    COPY_SYS_ATTR unraisablehook


  #TODO:interp
  SET_SYS "version", Py_GetVersion()

  SET_SYS("hexversion", newPyInt(PY_VERSION_HEX));

  SET_SYS("_git", Py_BuildValue("NPython", gitidentifier(),
                                gitversion()))

  #SET_SYS_FROM_STRING("_framework", PYTHONFRAMEWORK);
  SET_SYS("api_version", newPyInt(NPYTHON_API_VERSION))

  SET_SYS("copyright", Py_GetCopyright())
  SET_SYS("platform", PLATFORM);
  SET_SYS("maxsize", newPyInt(high int))


  SET_SYS("float_info", getFloatInfo())
  SET_SYS("int_info", getIntInfo())

  # initialize hash_info
  retIfExc PyStructSequence_InitBuiltin(interp, Hash_InfoType,
                                    Hash_info_desc)
  SET_SYS("hash_info", get_hash_info());

  SET_SYS("maxunicode", newPyInt(MAX_UNICODE))

  #SET_SYS("builtin_module_names", list_builtin_module_names());
  #SET_SYS("stdlib_module_names", list_stdlib_module_names());

  SET_SYS("byteorder", when cpuEndian==bigEndian:"big"else:"little")

  #[
  when MS_COREDLL:
    SET_SYS("dllhandle", PyLong_FromVoidPtr(PyWin_DLLhModule));
    SET_SYS_FROM_STRING("winver", PyWin_DLLVersionString);


  when declared ABIFLAGS:
    SET_SYS("abiflags", ABIFLAGS);
  ]#

  # version_info
  ENSURE_INFO_TYPE(VersionInfoType, Version_info_desc)
  let version_info = get_version_info()
  SET_SYS("version_info", version_info)

  # implementation
  SET_SYS("implementation", make_impl_info(version_info));

  #[
  # sys.flags: updated in-place later by _PySys_UpdateConfig()
  ENSURE_INFO_TYPE(FlagsType, flags_desc);
  SET_SYS("flags", make_flags(tstate.interp));

  when MS_WINDOWS:
    # getwindowsversion
    ENSURE_INFO_TYPE(WindowsVersionType, windows_version_desc);

    SET_SYS("_vpath", VPATH);

  # float repr style: 0.03 (short) vs 0.029999999999999999 (legacy)
  SET_SYS("float_repr_style", when PY_SHORT_FLOAT_REPR == 1:"short"else:"legacy");

  SET_SYS("thread_info", PyThread_GetInfo());

  # initialize asyncgen_hooks
  retIfExc PyStructSequence_InitBuiltin(interp, AsyncGenHooksType,
                                    asyncgen_hooks_desc)

  when defined(EMSCRIPTEN):
    if (EmscriptenInfoType == NULL) {
        EmscriptenInfoType = PyStructSequence_NewType(&emscripten_info_desc);
        if (EmscriptenInfoType == NULL) {
            goto type_init_failed;
        }
    }
    SET_SYS("_emscripten_info", make_emscripten_info());


  ]#
  # adding sys.path_hooks and sys.path_importer_cache
  SET_SYS("meta_path", newPyList())
  SET_SYS("path_importer_cache", newPyDict())
  SET_SYS("path_hooks", newPyList())
