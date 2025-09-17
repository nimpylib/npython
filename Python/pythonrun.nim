

import compile

import ./[asdl,
]
import ./pyimport/utils
import ../Parser/[lexer, apis,]
import ../Objects/bundle
import ../Utils/[utils, compat, fileio, trans_imp]
import ../Include/internal/pycore_global_strings

import ../Objects/[
  stringobjectImpl, exceptionsImpl,
  dictobject,
]
import ../Objects/stringobject/codec
from ./pylifecycle/utils import Py_FdIsInteractive
import ./pythonrun/utils
impExp pythonrun,
  pyerr, pyerr_sysexit_keyinter

using flags: PyCompilerFlags
using fp: fileio.File
using filename: PyStrObject
using globals, locals: PyDictObject

#var interp = (interactive_src_count: 0)

template run_modAux(interactive: static bool): untyped{.dirty.} =
  var interactive_filename = filename
  when interactive:
    if generate_new_source:
      #TODO: current when PyErr_Print, NPython calls printTb->fmtTraceBack->getSource
      #  which relies on fileName to look up source line on a table
      #    so we shall not change filename as long as this impl were not changed
      ##[
      template interactive_src_count: int = interp.interactive_src_count
      interactive_filename = filename & newPyAscii('-' & $interactive_src_count)
      interactive_src_count.inc
      ]##
  let compileRes = compile(modu, interactive_filename, flags)
  retIfExc compileRes
  let co = PyCodeObject compileRes
  when interactive:
    when declared(PyImport_ImportModuleAttr):
      let print_tb_func = PyImport_ImportModuleAttr("linecache", "_register_code")
      retIfExc print_tb_func
      if not print_tb_func.ofPyCallable:
        return newValueError newPyAscii "linecache._regester_code is not callable"
      retIfExc call(print_tb_func, co, interactive_src, filename)
  run_eval_code_with_audit(co, globals, locals)

using modu: AsdlModl
using pmod: var AsdlModl

proc run_mod(modu; filename; globals; locals: PyDictObject; flags; interactive_src: PyStrObject, generate_new_source=true): PyObject = run_modAux true
proc run_mod(modu; filename; globals; locals: PyDictObject; flags): PyObject = run_modAux false

using errcode: var ParseErrorcode

proc pyrun_one_parse_ast(fp; filename; flags; pmod; interactive_src: var PyInteractiveSrcObject, errcode): PyBaseErrorObject{.mayAsync, pyCFuncPragma.} =
  ## Call _PyParser_ASTFromFile() with sys.stdin.encoding, sys.ps1 and sys.ps2
  assert fp == stdin
  let (ps1, ps2, encoding) = getSysPsEnc()

  let res = mayAwait PyParser_InteractiveASTFromFile(fp, filename, encoding, Mode.Single, ps1, ps2,
    flags, errcode, interactive_src, pmod)
  interactiveHandleErrcode
  if pmod.isNil:
    return mayNewPromise res
  mayNewPromise PyBaseErrorObject nil


proc PyRun_InteractiveOneObjectEx(fp; filename; flags; main_dict: PyDictObject; interactive_src: var PyInteractiveSrcObject, errcode): PyBaseErrorObject{.mayAsync, pyCFuncPragma.} =
  ##[A PyRun_InteractiveOneObject() auxiliary function that does not print the
  error on failure.]##
  var modu: AsdlModl
  retIfExc pyrun_one_parse_ast(fp, filename, flags, modu, interactive_src, errcode)
  interactiveHandleErrcode

  # XXX: CPython here uses
  #   PyImport_AddModuleRef("__main__")
  #  we just cut dup condition check within this call by get main_dict first

  let res = run_mod(modu, filename, main_dict, main_dict, flags, interactive_src, true)
  if res.isThrownException:
    if res.ofPySyntaxErrorObject:
      # fix "text" attribute
      #assert not interactive_src.isNil
      #TODO:repl
      discard
    return mayNewPromise PyBaseErrorObject res

  flush_io()
  mayNewPromise PyBaseErrorObject nil

template getMainDict(excRes: untyped = true): PyDictObject =
  let res = PyImport_AddModuleRef("__main__")
  priRetIfExc(res, excRes)
  let main_module = PyModuleObject res
  main_module.getDict()

export PyRun_InteractiveLoopPre

template runIteractOneAndhandleExc =
  var errcode{.inject.}: ParseErrorcode
  let exc = mayAwait PyRun_InteractiveOneObjectEx(fp, filename, flags, main_dict, interactive_src, errcode)
  interactiveHandleErrcode true
  if not exc.isNil:
    PyErr_Print(exc)
    flush_io()

#[
proc KaraxRun_InteractiveOneObjectEx*(fp; filename; flags): bool{.mayAsync, pyCFuncPragma.} =
  ## unstable. export for karax backend
  let main_dict = getMainDict(mayNewPromise true)
  runIteractOneAndhandleExc
  false
]#

proc PyRun_InteractiveLoopObjectImpl(fp; filename; flags): bool {.mayAsync.} =
  ## returns if fails
  PyRun_InteractiveLoopPre()

  var interactive_src = newPyInteractiveSrc()
  let main_dict = getMainDict(mayNewPromise true)

  while true:
    runIteractOneAndhandleExc
  false


proc PyRun_InteractiveLoopObject*(fp; filename; flags): bool {.mayAsync, pyCFuncPragma.} =
  ## returns if fails
  mayAwait PyRun_InteractiveLoopObjectImpl(fp, filename, if flags.isNil: initPyCompilerFlags() else: flags)


proc PyRun_InteractiveLoopObject*(fp; filename): bool {.mayAsync, pyCFuncPragma.} =
  ## returns if fails
  mayAwait PyRun_InteractiveLoopObjectImpl(fp, filename, initPyCompilerFlags())

when NPythonAsyncReadline:
  converter upcast[T: PyObject](p: MayPromise[T]): MayPromise[PyObject] = p

using mode: Mode
proc pyrun_file(fp; filename; mode; globals; locals; closeit: bool; flags): PyObject{.mayAsync.} =
  var errcode: ParseErrorcode
  var modu: Asdlmodl
  retIfExc PyParser_ASTFromFile(fp, filename, "", mode, flags, errcode, modu)
  if closeit:
    fp.close
  
  mayNewPromise:
    if not modu.isNil:
      run_mod(modu, filename, globals, locals, flags)
    else: nil


proc PyRun_SimpleFileObject*(fp; filename; closeit=false; flags=initPyCompilerFlags()): bool{.mayAsync, pyCFuncPragma.} =
  ## `_PyRun_SimpleFileObject`
  let dict = getMainDict(mayNewPromise true)
  var res: PyObject
  let
    file = newPyAscii"__file__"
    cached = newPyAscii"__cached__"
  let has_file = dict.hasKey file
  var set_file_name = false
  template goto_done =
    if set_file_name:
      discard dict.pop(file, res)
      discard dict.pop(cached, res)
  if not has_file:
    dict[file] = filename
    dict[cached] = pyNone
    set_file_name = true
  

  #TODO:pyc maybe_pyc_file
  var pyc = false
  if pyc:
    discard
  else:
    #TODO:loader
    # When running from stdin, leave __main__.__loader__ alone
    res = mayAwait pyrun_file(fp, filename, Mode.File, dict, dict, closeit, flags)
  var result_v = false
  flush_io()
  if res.isThrownException:
    let exc = PyBaseErrorObject res
    PyErr_Print(exc)
    result_v = true
  goto_done
  result_v


proc PyRun_AnyFileObjectImpl(fp; filename; closeit=false, flags): bool{.mayAsync, pyCFuncPragma.} =
  ## `_PyRun_AnyFileObject`
  assert not filename.isNil
  var res: bool
  if Py_FdIsInteractive(fp, filename):
    res = mayAwait PyRun_InteractiveLoopObject(fp, filename, flags)
    if closeit:
      fp.close
  else:
    res = mayAwait PyRun_SimpleFileObject(fp, filename, closeit, flags)
  res

  
proc PyRun_AnyFileObject*(fp; filename: PyStrObject; closeit=false, flags=initPyCompilerFlags()): bool{.mayAsync, pyCFuncPragma.} =
  let filename = if filename.isNil: newPyAscii"???" else: filename
  PyRun_AnyFileObjectImpl(fp, filename, closeit, flags)

proc PyRun_AnyFileExFlags*(fp; filename: string; closeit=false, flags=initPyCompilerFlags()): bool{.mayAsync, pyCFuncPragma.} =
  let filename_obj = PyUnicode_DecodeFSDefault(filename)
  PyRun_AnyFileObjectImpl(fp, filename_obj, closeit, flags)


# main.c:pymain_repl
# pymain_start_pyrepl(1) or PyRun_AnyFileExFlags(stdin, "<stdin>", 0, &cf) where cf is _PyCompilerFlags_INIT
# 
# PyRun_AnyFileExFlags
#  PyRun_AnyFileExFlags

#[
proc PyRun_InteractiveOneObject*(fp; filename; flags): PyBaseErrorObject{.mayAsync, pyCFuncPragma.} =
  let main_dict = getMainDict(nil)
  var errcode: ParseErrorcode
  var res = mayAwait PyRun_InteractiveOneObjectEx(fp, filename, flags, main_dict, errcode)
  interactiveHandleErrcode
  if not res.isNil:
    PyErr_Print res
  res
]#
using str: string
proc PyRun_StringFlagsWithName(str; name: PyStrObject, mode; globals; locals; flags; generate_new_source: bool): PyObject{.raises: [].} =
  var modu: Asdlmodl
  Py_DECLARE_STR(anon_string, "<string>")
  var source: PyStrObject
  var name = name
  if not name.isNil:
    source = newPyStr(str)
  else:
    name = Py_STR(anon_string)
  retIfExc PyParser_ASTFromString(str, name, mode, flags, modu)
  result = run_mod(modu, name, globals, locals, flags, source, generate_new_source)

proc PyRun_StringFlags*(str; mode; globals; locals; flags=initPyCompilerFlags()): PyObject{.pyCFuncPragma.} =
  PyRun_StringFlagsWithName(str, nil, mode, globals, locals, flags, false)
template PyRun_String*(str; mode; globals; locals): PyObject =
  bind PyRun_StringFlags
  PyRun_StringFlags(str, mode, globals, locals)

template errPrint(dict; call){.dirty.} =
  let dict = getMainDict()
  let res = call
  if res.isThrownException:
    let exc = PyBaseErrorObject(res)
    PyErr_Print exc

proc PyRun_SimpleStringFlagsWithName*(str; name: string, flags=initPyCompilerFlags()): bool{.pyCFuncPragma.} =
  ## `_PyRun_SimpleStringFlagsWithName`
  errPrint dict:
    let the_name = newPyStr name
    PyRun_StringFlagsWithName(str, the_name, Mode.File, dict, dict, flags, false)

proc PyRun_SimpleStringFlags*(str; flags=initPyCompilerFlags()): bool{.pyCFuncPragma.} =
  #PyRun_SimpleStringFlagsWithName(str, nil, flags)
  errPrint dict:
    PyRun_StringFlags(str, Mode.File, dict, dict, flags)

proc PyRun_SimpleString*(str): bool = PyRun_SimpleStringFlags(str, initPyCompilerFlags())

