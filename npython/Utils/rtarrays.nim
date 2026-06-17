
const Js = defined(js)

when Js:
  {.define: esModule.}
  from std/jsffi import isNull
  import pkg/jscompat/utils/jsarrays
  #XXX: JsArray is ref-based instead of value-based,
  #FIXME: this causes some weirdness with equality and copying.
  type RtArray*[T] = JsArray[T]
  export jsarrays except JsArray, newJsArray, add
  proc initRtArray*[T](x: Natural): RtArray[T] = newJsArray[T](x)
  proc initRtArray*[T](x: openArray[T]): RtArray[T] = newJsArray[T](x)

  type
    RtArrayView*[T] = distinct JsArray[T]

  proc `[]`*[T](self: RtArrayView[T]; i: int): T =
    RtArray[T](self)[i]
  proc `[]=`*[T](self: RtArrayView[T]; i: int, val: T) =
    RtArray[T](self)[i] = val

  proc newView*[T](arr: RtArray[T]): RtArrayView[T] = RtArrayView[T](arr)
  proc isNil*(self: RtArrayView): bool = self.isNull

else:
  import ./rtarrays/[rawMem, rawMemView]
  export rawMem, rawMemView

when isMainModule:
  var arr = initRtArray [
    1, 2, 3
  ]
  echo $arr
  echo arr[2]
  echo arr == initRtArray [1,2,2]
  echo @arr == @[1,2,3]

  var v: RtArrayView[int]
  assert v.isNil
  assert not newView(arr).isNil
