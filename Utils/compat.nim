when defined(js):
  import strutils
  import std/jsconsole
  #[
  include karax/prelude
  var stream*: seq[(kstring, kstring)]
  proc log*(prompt, info: cstring) {. importc .}
  ]#

  # how to read from console?
  template readLineCompat*(prompt): string = 
    ""

  template echoCompat*(content: string) =
    echo content
    #stream.add((kstring"", kstring(content)))

  template errEchoCompat*(content) = 
    console.error content

  # Years ago...
  # combining two seq directly leaded to a bug in the compiler when compiled to JS
  # see gh-10651 (have been closed)
  template addCompat*[T](a, b: seq[T]) = 
    a.add b

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
    

