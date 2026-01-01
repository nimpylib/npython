
import xfail
class O:
    def __enter__(self):
        return self
    def __exit__(self, excType, excValue, traceback):
        if excType is not None:
             assert type(excValue) is excType
        pass

def nestedWith():
    with O() as o1:
        with O() as o2:
            assert type(o1) is O
            assert type(o2) is O
            assert o1 is not o2

nestedWith()

def nestedWith2():
    with O() as o1:
        with O() as o2:
            assert o1 is not o2
            raise ValueError
        assert False
    assert False

xfail.xfail(nestedWith2, ValueError)

def nestedWith3():
    with O() as o1:
        with O() as o2:
            assert o1 is not o2
        raise ValueError
    assert False

xfail.xfail(nestedWith3, ValueError)
