import os

cwd = os.getcwd()
cwdb = os.getcwdb()

assert type(cwd) is str
assert type(cwdb) is bytes
assert os.system(';' if os.name == 'nt' else 'true') == 0
assert os.chdir(cwd) is None
assert os.getcwd() == cwd

entries = os.listdir(".")
assert type(entries) is list
assert "npython.nim" in entries
