"""Estimate a word image's stroke slant: the shear that makes its
vertical strokes most upright (the sharpest column profile)."""
import numpy as np

def slant(gray, box, pad=4):
    x0, y0, x1, y1 = box
    crop = gray[max(0, y0 - pad):y1 + pad, max(0, x0 - pad):x1 + pad].astype(float)
    if crop.size == 0:
        return None
    thr = (crop.max() + crop.min()) / 2
    ink = (crop < thr).astype(float)
    # (The x-height band alone: a descender's tail, a y's, slants in
    # roman type too.)
    rows = ink.sum(1)
    if rows.max() > 0:
        dense = np.nonzero(rows > 0.45 * rows.max())[0]
        if len(dense) >= 6:
            ink = ink[dense[0]:dense[-1] + 1]
    h, w = ink.shape
    if ink.sum() < 30 or w < 8:
        return None
    ys = np.arange(h) - h / 2
    best, best_angle = -1, 0
    for deg in range(-8, 26, 2):
        t = np.tan(np.radians(deg))
        cols = np.zeros(w + h)
        for y in range(h):
            shift = int(round(ys[y] * t)) + h // 2
            row = ink[y]
            cols[shift:shift + w] += row
        score = (cols ** 2).sum()
        if score > best:
            best, best_angle = score, deg
    return best_angle
