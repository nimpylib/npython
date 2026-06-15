
import ./utils
template gen_ints_decl*(decl_int) {.dirty.} =
  bind catId, prefixCImpl
  macro decl_size(int; size: static[int]) =
    let intN = catId(int.strVal, $size)
    let cintN = prefixCImpl intN
    quote do:
      decl_int `cintN`, `intN`
    

  template decl_intN(int) {.dirty.} =
    decl_size int, 8
    decl_size int, 16
    decl_size int, 32
    decl_size int, 64

  type c_byte = int8
  type c_ubyte = uint8

  macro decl_ints(`u?`: static[string]) =
    result = newStmtList()
    let `u?int` = catId(`u?`, "int")
    result.add quote"@" do:
      decl_intN @`u?int`

    for i in [
      "byte", "int", "short", "long", "longlong",
    ]:
      let ii = catId(`u?`, i)
      let cii = prefixCImpl(ii)
      result.add quote do:
        decl_int `cii`, `cii`

  template decl_all_ints {.dirty.} =
    decl_ints ""
    decl_ints "u"

    decl_int c_size_t,  int
    decl_int c_ssize_t,uint

