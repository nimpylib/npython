def f():
  return "asd" \
   "bdc"

assert f() == "asdbdc"


assert("""123
b
 5""" == "123\nb\n 5")

assert("""123\
456
 abc""" == "123456\n abc")

assert [
  1,2,
'}'] == [1,2, '}']