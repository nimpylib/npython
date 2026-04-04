## Main Module that runs NPyhon Interpreter
## 
## An JavaScript-targeted online demo is available at <https://play.nimpylib.org>

when defined(js):
  include npython/Python/jspython
else:
  include npython/Python/cpython
