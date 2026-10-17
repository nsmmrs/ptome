"""What the scripts share: the work folder, the leaves of each part of
the book the work sets, and the printed page's measure."""
import os

WORK = os.environ.get('BCP_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/bcp'))

# The leaves (the Internet Archive's, of 10904662bsb) of each part.
PARTS = {
    'calendar': range(23, 35),
    'morning-prayer': range(45, 62),
    'litany': range(78, 87),
    'psalter': range(415, 643),
}
LEAVES = [n for r in PARTS.values() for n in r]

# The scan's pixels a point: its leaves 236 mm tall (Christie's, the
# 1760 octavo this reissues), 2,747 pixels.
PX = 2747 / (236 / 25.4 * 72)

# The printed page in points: the leaf (150 × 236 mm), the frame of
# flowers on it (frame.py's size, its top left at FX, FY), the text's
# edges inside it (INSIDE points in from the frame's rule each side).
PAGE = (425.2, 669.0)
FRAME = (348.98, 593.97)
FX, FY = (PAGE[0] - FRAME[0]) / 2, 28.0
INSIDE = 16.8


def to_page(g):
    """A leaf's pixels to the page's points (geometry.py's measures [g]),
    by its frame of flowers: (x, y) -> (x, y)."""
    x0, y0, x1, y1 = g['frame']['outer']
    sx, sy = (x1 - x0) / FRAME[0], (y1 - y0) / FRAME[1]
    return lambda x, y: (FX + (x - x0) / sx, FY + (y - y0) / sy)
