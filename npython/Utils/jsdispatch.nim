## this module's APIs is unstable
when defined(js):
  {.define: esModule.}
  import pkg/jscompat/utils/dispatch
  export dispatch
