
import xfail
def withint():
    with 42:
        assert False

xfail.xfail(withint, TypeError)
class O:
    def __enter__(self):
        return self
    def __exit__(self, excType, excValue, traceback):
        if excType is not None:
             assert type(excValue) is excType
        pass

def withClsSucc():
    with O() as o:
        assert type(o) is O
withClsSucc()


def withClsFail():
    o = O()
    with o as o2:
        assert o2 is o
        raise ValueError
    assert False

xfail.xfail(withClsFail, ValueError)


def withClsFail2():
    o = O()
    with o:
        assert type(o) is O
        raise ValueError
    assert False

xfail.xfail(withClsFail2, ValueError)


def withMulti():
    with O() as o1, O() as o2:
        assert type(o1) is O
        assert type(o2) is O
        assert o1 is not o2

withMulti()


def withMultiFail():
    with O() as o1, O() as o2:
        assert type(o1) is O
        assert type(o2) is O
        raise ValueError
    assert False

xfail.xfail(withMultiFail, ValueError)



def nestedWithFail():
    with O() as o1:
        with O() as o2:
            assert type(o1) is O
            assert type(o2) is O
            assert o1 is not o2
            raise ValueError
    assert False

xfail.xfail(nestedWithFail, ValueError)

