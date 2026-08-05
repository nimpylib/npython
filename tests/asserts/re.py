import re

m = re.search(r"(world)", "hello world")
assert m.group(0) == "world"
assert m.group(1) == "world"
assert re.search(r"^hello", "hello world").group(0) == "hello"
assert re.findall(r"[a-z]+", "one two") == ["one", "two"]
assert re.sub(r"cat", "dog", "cat cat") == "dog dog"
assert re.split(r",", "a,b,c") == ["a", "b", "c"]

pattern = re.compile(r"world")
assert pattern.search("hello world").group(0) == "world"
