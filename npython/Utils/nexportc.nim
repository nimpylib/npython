
import ./nexportc_header
export nexportc_header
when appType == "lib" or defined(wasm):
  import ./nexportcImpl
  export nexportcImpl
else:
  template npyexportc*(def) = def
  template npyexportcSet*(flags: NPyExportcFlagsSet; def) = def

