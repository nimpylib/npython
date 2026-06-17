
import pkg/handy_sugars/trans_imp
impExpCwd memoryobject, [
  decl, status,
]
when NPySupportRawMemory:
  impExpCwd memoryobject, [
    constructors, deconstructors, abstract, methods,
  ]

#implMemoryViewMagic getitem:

