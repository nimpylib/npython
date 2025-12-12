def main():
    try:
        assert False
    except:
        pass


main()


def catch():
    try:
        assert False
    except AssertionError:
        pass

catch()


def nocatch():
    try:
        a
    except AssertionError:
        pass



def get_name_error(fun):
    flag = False
    try:
        fun()
    except NameError:
        flag = True

    assert flag


get_name_error(nocatch)


def multiple_except():
    flag = False
    try:
        multiple
    except ValueError:
        pass
    except NameError:
        flag = True
    except AssertionError:
        a = 1+2

    assert flag


multiple_except()

print("nested exception with A B C means ok")


def nested():
    try:
        a
    except:
        try:
            b
        except:
            c

try:
    nested()
except NameError as e:
    assert str(e) == "name 'c' is not defined"

