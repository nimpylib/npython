when defined(js):
  import strutils
  #[
  include karax/prelude
  var stream*: seq[(kstring, kstring)]
  ]#
  proc log*(prompt, info: cstring) {. importc .}

  # how to read from console?
  template readLineCompat*(prompt): string = 
    ""

  template echoCompat*(content: string) =
    echo content
    for line in content.split("\n"):
      log(cstring" ", line)
    #stream.add((kstring"", kstring(content)))

  template errEchoCompat*(content) = 
    echoCompat content

  # combining two seq directly leads to a bug in the compiler when compiled to JS
  # see gh-10651
  template addCompat*[T](a, b: seq[T]) = 
    for item in b:
      a.add item

else:
  import rdstdin


  template readLineCompat*(prompt): string = 
    readLineFromStdin(prompt)

  template echoCompat*(content) = 
    echo content

  template errEchoCompat*(content) = 
    stderr.writeLine content

  template addCompat*[T](a, b: seq[T]) = 
    a.add b
    

