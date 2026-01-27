
assert f"" == ""

assert f"asd" == "asd"
assert f"as\nd" == "as\nd"
assert fr"as\nd" == r"as\nd"

a = 123
assert f"as{a}d$" == r"as123d$"

st = "123"
assert f"as0{st:.2}d" == r"as012d"

assert f"as0{st:.2}dac{43.5}.$" == r"as012dac43.5.$"

assert f"as0{st!r}dac{43.5 + 1}.$" == r"as0'123'dac44.5.$"


assert f"asb{st:.{1}{'s'}}dac{43.5 + 1}.$" == r"asb1dac44.5.$"

assert f"""asb{st!r}dac{43.5 + 1}.$""" == r"""asb'123'dac44.5.$"""

assert f"""b
asb{st!r}dac{43.5 + 1}
.$""" == """b\nasb'123'dac44.5\n.$"""


assert f"asb{ {st} }dac{43.5 + 1}.$" == r"asb{'123'}dac44.5.$"

assert f"0^{st=:.2}$1" == r"0^st=12$1"
