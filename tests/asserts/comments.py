# A whole-line comment must be ignored.

value = 40  # A trailing comment must be ignored too.
value += 2  # Another trailing comment.

# Comments between statements must not affect parsing.
assert value == 42  # Trailing comment on an assertion.
