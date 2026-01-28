
def get_cell_contents(closure):
    return tuple([i.cell_contents for i in closure])

def f():
    outter = -1
    def ff():
        return outter
    # outter is referenced by nested function ff
    assert f.__code__.co_cellvars == ("g", "outter",)
    assert f.__code__.co_varnames == ("ff",)
    def g(a, b, *, c=1, d=2, e=3):
        assert f.__name__ == "f"

        co = g.__code__

        assert co.co_freevars == ("g",)
        assert get_cell_contents(g.__closure__) == (g,)

        assert co.co_argcount == 2
        assert co.co_kwonlyargcount == 3

        assert len(co.co_varnames) == co.co_nlocals
        assert co.co_nlocals == 6
        # a, b, c, d, e, co
    g(10, 11)

f()
