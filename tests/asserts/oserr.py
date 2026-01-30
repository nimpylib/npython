
e=OSError()
assert not hasattr(e, "characters_written")

e.characters_written = 42
assert e.characters_written == 42

assert e.filename is None
