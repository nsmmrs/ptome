"""Writes vendor/erfa/*.tsv from ERFA's C sources (BSD-3-Clause, LICENSE):
the coefficients the calendars' astronomy uses.

- earth.tsv: eraEpv00's Sun-to-Earth series (its ecliptic frame, before
  the rotation to the BCRS): component (x, y, z), power of T (0 to 2),
  amplitude (au), phase (rad), frequency (rad per Julian year).
- moon.tsv: eraMoon98's (Meeus') series: `lr`, the multiples of D, M,
  M' and F and the longitude (deg) and distance (m) coefficients; `b`,
  the multiples and the latitude coefficient (deg).
- nutation.tsv: eraNut00b's (IAU 2000B) luni-solar terms: the multiples
  of l, l', F, D and Om, then the longitude's sine, t sine and cosine
  coefficients and the obliquity's (0.1 microarcsec).

    python3 -I tool/import_erfa.py ERFA_SRC_DIR
"""
import os
import re
import sys


def arrays(text, names):
    """The numbers of each C array named in [names]."""
    found = {}
    for name in names:
        m = re.search(r'%s\s*\[\]\s*=\s*\{(.*?)\};' % re.escape(name), text,
                      re.S)
        body = re.sub(r'/\*.*?\*/', '', m.group(1), flags=re.S)
        found[name] = [float(n) for n in re.findall(
            r'[-+]?\d+\.?\d*(?:[eEdD][-+]?\d+)?', body)]
    return found


def main():
    src = sys.argv[1]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    vendor = os.path.join(root, 'vendor/erfa')
    epv = open(os.path.join(src, 'epv00.c')).read()
    names = ['e%d%s' % (p, c) for p in range(3) for c in 'xyz']
    tables = arrays(epv, names)
    with open(os.path.join(vendor, 'earth.tsv'), 'w') as out:
        out.write('# From ERFA (eraEpv00, epv00.c), BSD-3-Clause (LICENSE):\n'
                  '# the Sun-to-Earth series, ecliptic frame.\n'
                  '# component, power, amplitude (au), phase (rad),\n'
                  '# frequency (rad/Julian year)\n')
        for name in names:
            values = tables[name]
            for i in range(0, len(values), 3):
                out.write('%s\t%s\t%r\t%r\t%r\n' % (
                    name[2], name[1], values[i], values[i + 1],
                    values[i + 2]))
    moon = open(os.path.join(src, 'moon98.c')).read()
    lr = re.search(r'tlr\[\]\s*=\s*\{(.*?)\};', moon, re.S).group(1)
    b = re.search(r'tb\[\]\s*=\s*\{(.*?)\};', moon, re.S).group(1)
    with open(os.path.join(vendor, 'moon.tsv'), 'w') as out:
        out.write('# From ERFA (eraMoon98, moon98.c), BSD-3-Clause (LICENSE):\n'
                  '# Meeus\' lunar series. lr: D, M, M\', F, longitude\n'
                  '# (deg), distance (m); b: D, M, M\', F, latitude (deg)\n')
        for kind, body, width in (('lr', lr, 6), ('b', b, 5)):
            for term in re.findall(r'\{([^{}]*)\}', body):
                values = [v.strip() for v in term.split(',')]
                assert len(values) == width, term
                out.write('%s\t%s\n' % (kind, '\t'.join(values)))
    nut = open(os.path.join(src, 'nut00b.c')).read()
    body = re.search(r'\}\s*x\[\]\s*=\s*\{(.*?)\n\s*\};', nut, re.S).group(1)
    body = re.sub(r'/\*.*?\*/', '', body, flags=re.S)
    with open(os.path.join(vendor, 'nutation.tsv'), 'w') as out:
        out.write('# From ERFA (eraNut00b, nut00b.c), BSD-3-Clause (LICENSE):\n'
                  '# IAU 2000B luni-solar nutation. l, l\', F, D, Om; dpsi\n'
                  '# sin, t sin, cos; deps cos, t cos, sin (0.1 uas)\n')
        for term in re.findall(r'\{([^{}]*)\}', body):
            values = [v.strip() for v in term.split(',')]
            assert len(values) == 11, term
            out.write('\t'.join(values) + '\n')


main()
