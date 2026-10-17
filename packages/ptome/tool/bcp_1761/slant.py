"""Whether a word on the scan is italic: the shear of its ink that sets
its stems most upright (the column profile's sum of squares the
greatest), Baskerville's italic leaning about a sixth, its roman not at
all; a word sheared past SLANT, italic.

    from slant import slant
"""
import numpy as np

SHEARS = np.linspace(-0.05, 0.35, 17)
SLANT = 0.11


def slant(ink):
    """The shear (x shift per row, rightward up) that makes [ink], a
    word's box of booleans, most upright."""
    h, w = ink.shape
    if h < 8 or w < 8 or ink.sum() < 30:
        return 0.0
    ys, xs = np.nonzero(ink)
    best, at = -1.0, 0.0
    for s in SHEARS:
        # (Each row moved right by its height over the baseline times s.)
        cols = np.round(xs + (ys - (h - 1)) * s).astype(int)
        cols -= cols.min()
        prof = np.bincount(cols)
        score = float((prof.astype(float) ** 2).sum())
        if score > best:
            best, at = score, float(s)
    return at
