import os
from pathlib import Path

cwd = os.getcwd()
cwdb = os.getcwdb()

assert type(cwd) is str
assert type(cwdb) is bytes
assert os.system(';' if os.name == 'nt' else 'true') == 0
assert os.chdir(cwd) is None
assert os.getcwd() == cwd

p = Path(__file__)
entries = os.listdir(p.parent)
assert type(entries) is list
assert p.name in entries

default_entries = os.listdir()
assert type(default_entries) is list

