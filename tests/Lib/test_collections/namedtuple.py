
from collections import namedtuple

Point = namedtuple('Point', ['x', 'y'])
p = Point(1, 2)
assert p.x == 1
assert p.y == 2

assert p[0] == 1
assert p[1] == 2

assert repr(p) == 'Point(x=1, y=2)'



Point2 = namedtuple('Point2', ['x', 'y'], defaults=[3])
p2 = Point2(1)
assert p2.x == 1
assert p2.y == 3

assert p2._field_defaults == {'y': 3}
assert p2._asdict() == {'x': 1, 'y': 3}

assert Point2._make([4, 5]) == Point2(4, 5)
assert p2._replace(y=6) == Point2(1, 6)
