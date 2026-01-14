

const PY_STACK_USE_GUIDELINE* = 30
  ##[`_PY_STACK_USE_GUIDELINE`
A soft limit for stack use, to avoid excessive
memory use for large constants, etc.

The value 30 is plucked out of thin air.
Code that could use more stack than this is
rare, so the exact value is unimportant.
]##