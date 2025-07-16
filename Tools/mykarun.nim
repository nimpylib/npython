
import std / [os, strutils, browsers, strformat, parseopt]

const
  css = """
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/bulma/0.7.4/css/bulma.min.css">
  <link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/font-awesome/4.7.0/css/font-awesome.min.css">
"""
  html = """
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8"/>
  <meta content="width=device-width, initial-scale=1" name="viewport"/>
  <title>$1</title>
  $2
</head>
<body id="body" class="site">
<div id="ROOT">$3</div>
$4
</body>
</html>
"""


proc exec(cmd: string) =
  if os.execShellCmd(cmd) != 0:
    quit "External command failed: " & cmd

const Buf = 1024
proc extend(outf, inf: File) =
  var buf: array[Buf, uint8]
  while true:
    let n = inf.readBytes(buf, 0, Buf)
    if n == 0: break
    let wn = outf.writeBytes(buf, 0, n)
    assert n == wn
proc extendNJsFileAndCompress(outf, inf: File) =
  var line: string
  while true:
    line = inf.readLine
    outf.writeLine line.strip(true, false, {' '})  # we know Nim current only use spaces for indentation
    if inf.endOfFile:
      break

proc build(ssr: bool, entry: string, rest: string, selectedCss: string, run: bool,
    watch: bool,
    jsDir, appName: string, htmlName=appName, includeJs = false,
    release=false,
    ) =
  echo("Building...")
  var cmd: string
  var content = ""
  var outTempPath: string
  var outHtmlName: string
  let jsFp = jsDir / appName & ".js"
  if ssr: 
    outHtmlName = changeFileExt(extractFilename(entry),"html")
    outTempPath = getTempDir() / outHtmlName
    cmd = "nim c -r " & rest & " " &  outTempPath 
  else:
    cmd = "nim js --out:" & jsFp & ' ' & rest
  if watch:
    discard os.execShellCmd(cmd)
  else:
    exec cmd
  let dest = htmlName & ".html"
  if ssr: 
    content = readFile(outTempPath)
  if includeJs:
    defer: removeFile jsFp
    assert not ssr, "includeJs and ssr are exclusive"
    let parts = html.split("$4", 1)
    assert parts.len == 2
    var outF = open(dest, fmWrite)
    outF.write parts[0] % [appName, selectedCss, ""]
    outF.write"""<script type="text/javascript">"""
    outF.write '\n'
    let inF = open(jsFp)
    if release:
      outF.extendNJsFileAndCompress inf
    else:
      outF.extend inF
    inF.close()
    outF.write '\n'
    outF.write"""</script>"""
    outF.write parts[1]
    outF.close()
  else:
    let script = if ssr:"" else: &"""<script type="text/javascript" src="{jsFp}"></script>""" # & (if watch: websocket else: "")
    writeFile(dest, html % [if ssr: outHtmlName else:appName, selectedCss,content, script])
  if run: openDefaultBrowser("http://localhost:8080")

proc main =
  var op = initOptParser()
  var rest: string
  var
    jsDir = ""  # root
    appName = "app"
    htmlName = appName
    htmlNameGiven = false
    includeJs = false
  var file = ""
  var run = false
  var watch = false
  var selectedCss = ""
  var ssr = false

  template addToRestAux =
    rest.add op.key
    if op.val != "":
      rest.add ':'
      rest.add op.val

  while true:
    op.next()
    case op.kind
    of cmdLongOption:
      case op.key
      of "htmlName":
        htmlName = op.val
        htmlNameGiven = true
      of "appName":
        appName = op.val
      of "jsDir":
        jsDir = op.val
      of "includeJs":
        includeJs = true
      of "run":
        run = true
      of "css":
        if op.val != "":
          selectedCss = readFile(op.val)
        else:
          selectedCss = css
      of "ssr":
        ssr = true
      else:
        rest.add " --"
        addToRestAux
    of cmdShortOption:
      if op.key == "r":
        run = true
      elif op.key == "w":
        watch = true
      elif op.key == "s":
        ssr = true
      else:
        rest.add " -"
        addToRestAux
    of cmdArgument:
      file = op.key
      rest.add ' '
      rest.add file
    of cmdEnd: break

  if file.len == 0: quit "filename expected"
  # if run:
  #   spawn serve()
  # if watch:
  #   spawn watchBuild(ssr, file, selectedCss, rest)
  if not htmlNameGiven:
    htmlName = appName
  build(ssr, file, rest, selectedCss, run, watch,
    jsDir, appName, htmlName,
    includeJs,
    "-d:release" in rest  # XXX: not exhaustive
    )
  # sync()

main()
