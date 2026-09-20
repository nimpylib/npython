
type
  Scope* {. pure .} = enum
    Local,
    Cell,
    Free,
    Global

  SteKind* {. pure .} = enum
    Module, Function, Class
