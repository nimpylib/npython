def f():
  return "asd" \
   "bdc"

assert f() == "asdbdc"
assert("""123
""" == "123\n")

assert("""123\
456""" == "123456")

assert [
  1,2,
'}'] == [1,2, '}']