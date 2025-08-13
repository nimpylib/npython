
const Js = defined(js)

when Js:
  import ./rtarrays/jsArrays
  type RtArray*[T] = JsArray[T]
  export jsArrays except JsArray, newJsArray, add
  proc initRtArray*[T](x: int): RtArray[T] = newJsArray[T](x)
  proc initRtArray*[T](x: openArray[T]): RtArray[T] = newJsArray[T](x)

else:
  import ./rtarrays/rawMem
  export rawMem

when isMainModule:
  var arr = initRtArray [
    1, 2, 3
  ]
  echo $arr
  echo arr[2]
  echo arr == initRtArray [1,2,2]
  echo @arr == @[1,2,3]
