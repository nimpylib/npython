
import std/tables
import ../[
  pyobject,
  stringobject,
  dictobject,
  funcobject,
  methodobject,
  descrobject,
]
import ./default_generics
import ../../Include/internal/[
  pycore_global_strings,
]
import ../pyobject_apis/[
  attrsGeneric, strings,
]
import ./[decl, utils,]

using typ: PyTypeObject

proc typeReady*(tp: PyTypeObject){.pyCFuncPragma.} ## PyType_Ready
using typ: PyTypeObject
proc PyType_IsReady(typ): bool =
  not typ.dict.isNil
proc type_ready_set_base(typ){.pyCFuncPragma.} =
  # Initialize tp_base (defaults to BaseObject unless that's us)
  var base = typ.base
  if base.isNil and not typ.isType pyObjectType:
    base = pyObjectType
    typ.base = base
  
  #[Now the only way base can still be NULL is if type is
  &PyBaseObject_Type.]#

  # Initialize the base class
  if not base.isNil and not PyType_IsReady(base):
    typeReady(base)


proc inherit_slots(typ; base: PyTypeObject){.pyCFuncPragma.} =
  var basebase: PyTypeObject

  template RAW_SLOTDEFINED(SLOT): bool =
    (not base.SLOT.isNil and
     (basebase.isNil or base.SLOT != basebase.SLOT))
  template tp(tpObj): untyped = tpObj.magicMethods
  template SLOTDEFINED(SLOT): bool =
    (not base.tp.SLOT.isNil and
     (basebase.isNil or base.tp.SLOT != basebase.tp.SLOT))

  template do_RAW_COPYSLOT(SLOT) =  typ.SLOT = base.SLOT
  template RAW_COPYSLOT(SLOT) =
    if typ.SLOT.isNil and RAW_SLOTDEFINED(SLOT): do_RAW_COPYSLOT(SLOT)

  template do_COPYSLOT(SLOT) =  typ.magicMethods.SLOT = base.magicMethods.SLOT
  template COPYSLOT(SLOT) =
    if typ.magicMethods.SLOT.isNil and SLOTDEFINED(SLOT): do_COPYSLOT SLOT
  template addalias(name) =
    template name(SLOT) = COPYSLOT(SLOT)
  addalias COPYNUM
  addalias COPYASYNC
  addalias COPYSEQ
  addalias COPYBUF
  #[ This won't inherit indirect slots (from tp_as_number etc.)
       if type doesn't provide the space. ]#

  block: #  if (type->tp_as_number != NULL && base->tp_as_number != NULL) {
        basebase = base.base
        
        COPYNUM(add);
        COPYNUM(sub);
        COPYNUM(mul);
        COPYNUM(Mod);
        COPYNUM(divmod);
        COPYNUM(pow);
        COPYNUM(negative);
        COPYNUM(positive);
        COPYNUM(abs);
        COPYNUM(bool);
        COPYNUM(invert);
        COPYNUM(lshift);
        COPYNUM(rshift);
        COPYNUM(And);
        COPYNUM(Xor);
        COPYNUM(Or);
        COPYNUM(int);
        COPYNUM(float);
        COPYNUM(iadd);
        COPYNUM(isub);
        COPYNUM(imul);
        COPYNUM(imod);
        COPYNUM(ipow);
        COPYNUM(ilshift);
        COPYNUM(irshift);
        COPYNUM(iand);
        COPYNUM(ixor);
        COPYNUM(ior);
        COPYNUM(true_div);
        COPYNUM(floor_div);
        COPYNUM(itrue_div);
        COPYNUM(ifloor_div);
        COPYNUM(index);
        COPYNUM(matmul);
        COPYNUM(imatmul);

        COPYASYNC(await);
        COPYASYNC(aiter);
        COPYASYNC(anext);

        COPYSEQ(len);
        #COPYSEQ(sq_concat);
        #COPYSEQ(sq_repeat);
        COPYSEQ(getitem);
        COPYSEQ(setitem);
        COPYSEQ(contains);
        #COPYSEQ(sq_inplace_concat);
        #COPYSEQ(sq_inplace_repeat);


        COPYBUF(buffer);
        COPYBUF(release_buffer);


  basebase = base.base

  RAW_COPYSLOT(tp_dealloc);
  if typ.tp.getattr.isNil:
      do_COPYSLOT getattr
      #type->tp_getattro = base->tp_getattro;

  if typ.tp.setattr.isNil:
      do_COPYSLOT setattr
      #type->tp_setattro = base->tp_setattro;

  COPYSLOT(repr);
  # tp_hash see tp_richcompare
  block:
      #[/* Always inherit tp_vectorcall_offset to support PyVectorcall_Call().
        * If Py_TPFLAGS_HAVE_VECTORCALL is not inherited, then vectorcall
        * won't be used automatically. */]#

        #[
      COPYSLOT(tp_vectorcall_offset);

      # Inherit Py_TPFLAGS_HAVE_VECTORCALL if tp_call is not overridden
      if (!type->tp_call &&
          _PyType_HasFeature(base, Py_TPFLAGS_HAVE_VECTORCALL))
      {
          type_add_flags(type, Py_TPFLAGS_HAVE_VECTORCALL);
      }]#
      COPYSLOT(call);
  COPYSLOT(str);
  block:
      #[ Copy comparison-related slots only when
          not overriding them anywhere ]#
      proc useDefaultRichcompare(typ: PyTypeObject): bool =
        typ.tp.le == leDefault and
          typ.tp.eq == eqDefault and
          typ.tp.ne == neDefault
      if typ.useDefaultRichcompare and
            typ.tp.hash == hashDefault:
          proc overrides_hash(typ: PyTypeObject): bool {.cdecl.} =
            let dict = PyDictObject typ.dict;
            assert not dict.isNil
            result = hasKey(dict, pyDUId(eq))
            if not result:
              result = hasKey(dict, pyDUId(hash))
          let r = overrides_hash(typ)
          if not r:
            do_COPYSLOT le
            do_COPYSLOT eq
            do_COPYSLOT ne
            #typ.tp.richcompare = base.tp.richcompare
            do_COPYSLOT hash
  block:
      COPYSLOT(iter)
      COPYSLOT(iternext)
  block:
      COPYSLOT(get);
      #[ Inherit Py_TPFLAGS_METHOD_DESCRIPTOR if tp_descr_get was inherited,
        but only for extension types ]#
        #[
      if not base.get.isNil and
          typ.get == base.get and
          _PyType_HasFeature(type, Py_TPFLAGS_IMMUTABLETYPE) &&
          _PyType_HasFeature(base, Py_TPFLAGS_METHOD_DESCRIPTOR))
          type_add_flags(type, Py_TPFLAGS_METHOD_DESCRIPTOR);
      }]#
      COPYSLOT(set);
      #COPYSLOT(tp_dictoffset);
      COPYSLOT(init);
      RAW_COPYSLOT(tp_alloc);
      #COPYSLOT(tp_is_gc);
      #RAW_COPYSLOT(tp_finalize);
      RAW_COPYSLOT(tp_dealloc);
      #[
      if ((type->tp_flags & Py_TPFLAGS_HAVE_GC) ==
          (base->tp_flags & Py_TPFLAGS_HAVE_GC)) {
          # They agree about gc.
          COPYSLOT(tp_free);
      }
      else if ((type->tp_flags & Py_TPFLAGS_HAVE_GC) &&
                type->tp_free == NULL &&
                base->tp_free == PyObject_Free) {
          #[/* A bit of magic to plug in the correct default
            * tp_free function when a derived class adds gc,
            * didn't define tp_free, and the base uses the
            * default non-gc tp_free.
            */]#
          type->tp_free = PyObject_GC_Del;
          ]#
      #[/* else they didn't agree about gc, and there isn't something
        * obvious to be done -- the type is on its own.
        */]#

proc inherit_special(typ; base: PyTypeObject) =
  if typ.tp_basicsize == 0:
    typ.tp_basicsize = base.tp_basicsize;

proc type_ready_inherit(typ) =
  let base = typ.base
  if not base.isNil:
    inherit_special typ, base
  # Inherit slots
  forMroNoSelf b, typ:
    if b.ofPyTypeObject:
      inherit_slots(typ, b)

#TODO: _Py_type_getattro_impl,_Py_type_getattro, then update ./pyobject_apis/attrs
proc addGeneric(t: PyTypeObject) = 
  template nilMagic(magicName): bool = 
    t.magicMethods.magicName.isNil

  template trySetSlot(magicName, defaultMethod) = 
    if nilMagic(magicName):
      t.magicMethods.magicName = defaultMethod

  if (not nilMagic(lt)) and (not nilMagic(eq)):
    trySetSlot(le, leDefault)
  if (not nilMagic(eq)):
    trySetSlot(ne, neDefault)
  else:
    trySetSlot(ne, neDefault)
  if (not nilMagic(ge)) and (not nilMagic(eq)):
    trySetSlot(ge, geDefault)
  trySetSlot(eq, eqDefault)
  trySetSlot(getattr, PyObject_GenericGetAttr)
  trySetSlot(setattr, PyObject_GenericSetAttr)
  trySetSlot(delattr, PyObject_GenericDelAttr)
  trySetSlot(repr, reprDefault)
  trySetSlot(hash, hashDefault)
  trySetSlot(str, t.magicMethods.repr)



proc type_add_members(tp: PyTypeObject, dict: PyDictObject) =
  for memb in tp.members:
    let descr = newPyMemberDescr(tp, memb)
    assert not descr.isNil
    let failed = dict.setDefaultRef(descr.name, descr) == GetItemRes.Error
    assert not failed


# for internal objects
proc initTypeDict(tp: PyTypeObject) = 
  assert tp.dict.isNil
  let d = newPyDict()
  # magic methods. field loop syntax is pretty weird
  # no continue, no enumerate
  var i = -1
  for meth in tp.magicMethods.fields:
    inc i
    if not meth.isNil:
      let namePyStr = magicNameStrs[i]
      if meth is BltinFunc:
        d[namePyStr] = newPyStaticMethod(newPyNimFunc(meth, namePyStr))
      else:
        d[namePyStr] = newPyMethodDescr(tp, meth, namePyStr)

  type_add_members(tp, d)

  # getset descriptors.
  for key, value in tp.getsetDescr.pairs:
    let getter = value[0]
    let setter = value[1]
    let descr = newPyGetSetDescr(getter, setter)
    let namePyStr = newPyStr(key)
    d[namePyStr] = descr
   
  # bltin methods
  for name, (meth, classmethod) in tp.bltinMethods.pairs:
    let namePyStr = newPyAscii(name)
    d[namePyStr] = 
      if classmethod: newPyClassMethodDescr(tp, meth, namePyStr)
      else: newPyMethodDescr(tp, meth, namePyStr)

  tp.dict = d


proc typeReadyImpl*(tp: PyTypeObject, initial: bool) = 
  ## unstable. innner.
  type_ready_set_base tp
  tp.addGeneric
  if tp.dict.isNil:
    tp.initTypeDict
  if initial:
    type_ready_inherit tp

proc typeReady*(tp: PyTypeObject, initial: bool){.pyCFuncPragma.} = 
  # unstable. type_ready_set_type
  if tp.pyType.isNil:
    tp.pyType = pyTypeObjectType
  tp.typeReadyImpl initial


proc typeReady*(tp: PyTypeObject) = 
  # Py_TPFLAGS_READY
  if tp.PyType_IsReady:
    return
  tp.typeReady true
