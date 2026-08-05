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
assert re.search("world", b"hello world").group(0) == "world"
assert re.search("world", bytearray([104, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100])).group(0) == "world"
assert re.findall("[a-z]+", b"one two") == ["one", "two"]
assert re.sub("cat", "dog", bytearray([99, 97, 116, 32, 99, 97, 116])) == "dog dog"
assert re.split(",", b"a,b,c") == ["a", "b", "c"]
assert pattern.search(bytearray([104, 101, 108, 108, 111, 32, 119, 111, 114, 108, 100])).group(0) == "world"
