
import ./initUtils
import ../../Python/[
  getversion, modsupport,
]
import ../../Include/[
  modsupport,
]
import ../../Modules/[
  getbuildinfo,
]

#TODO:PyStructSequence
#proc make_version_info(): PyObject =

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

  #SET_SYS("hexversion", newPyInt(PY_VERSION_HEX));

  SET_SYS("_git", Py_BuildValue("NPython", gitidentifier(),
                                gitversion()))

  #SET_SYS_FROM_STRING("_framework", PYTHONFRAMEWORK);
  SET_SYS("api_version", newPyInt(NPYTHON_API_VERSION))

  #[
  SET_SYS("copyright", Py_GetCopyright());
  SET_SYS("platform", Py_GetPlatform());
  ]#
  SET_SYS("maxsize", newPyInt(high int))
  #[
  SET_SYS("float_info", PyFloat_GetInfo());
  SET_SYS("int_info", PyLong_GetInfo());
  # initialize hash_info
  retIfExc PyStructSequence_InitBuiltin(interp, Hash_InfoType,
                                    hash_info_desc)
  SET_SYS("hash_info", get_hash_info(tstate));
  ]#

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

  template ENSURE_INFO_TYPE(TYPE, DESC) =
      retIfExc PyStructSequence_InitBuiltinWithFlags(
              interp, TYPE, DESC, Py_TPFLAGS_DISALLOW_INSTANTIATION)

  # version_info
  ENSURE_INFO_TYPE(VersionInfoType, version_info_desc);
  version_info = make_version_info(tstate);
  SET_SYS("version_info", version_info);

  # implementation
  SET_SYS("implementation", make_impl_info(version_info));

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
