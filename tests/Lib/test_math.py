import math


def assert_raises(exc_type, func, *args):
    raised = False
    try:
        func(*args)
    except exc_type:
        raised = True
    assert raised


def assert_nan(x):
    assert math.isnan(x)


def test_sumprod_core():
    assert math.sumprod([10, 20, 30], [1, 2, 3]) == 140
    assert math.sumprod([1.5, 2.5], [3.5, 4.5]) == 16.5
    assert math.sumprod([], []) == 0
    assert math.sumprod([-1.0], [1.0]) == -1.0
    assert math.sumprod([1], [-1]) == -1
    assert math.sumprod([True, False, True], [5.0, 10.0, 7.0]) == 12.0


def test_sumprod_uneven_lengths():
    assert_raises(ValueError, math.sumprod, [10, 20], [30])
    assert_raises(ValueError, math.sumprod, [10], [20, 30])


def test_sumprod_bigints_and_fallback():
    assert math.sumprod([10**20], [1]) == 10**20
    assert math.sumprod([1], [10**20]) == 10**20
    assert math.sumprod([10**3], [10**3]) == 10**6


def test_sumprod_special_values():
    assert math.sumprod([10.1, math.inf], [20.2, 30.3]) == math.inf
    assert math.sumprod([10.1, math.inf], [math.inf, 30.3]) == math.inf
    assert math.sumprod([10.1, math.inf], [math.inf, math.inf]) == math.inf
    assert math.sumprod([10.1, -math.inf], [20.2, 30.3]) == -math.inf
    assert_nan(math.sumprod([10.1, math.inf], [-math.inf, math.inf]))
    assert_nan(math.sumprod([10.1, math.nan], [20.2, 30.3]))
    assert_nan(math.sumprod([10.1, math.inf], [math.nan, 30.3]))
    assert_nan(math.sumprod([10.1, math.inf], [20.3, math.nan]))


def test_sumprod_errors():
    assert_raises(TypeError, math.sumprod)
    assert_raises(TypeError, math.sumprod, [0])
    assert_raises(TypeError, math.sumprod, None, [10])
    assert_raises(TypeError, math.sumprod, [10], None)
    assert_raises(TypeError, math.sumprod, ["abc", 3], [5, 10])
    assert_raises(TypeError, math.sumprod, [5, 10], ["abc", 3])


test_sumprod_core()
test_sumprod_uneven_lengths()
test_sumprod_bigints_and_fallback()
test_sumprod_special_values()
test_sumprod_errors()
