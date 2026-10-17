"""Each cut floated to a side its foot (adjust.json's `foot/ID`, gen.py's):
how far past the last line beside it, on the scan, the float reaches,
as the engine sets that line beside it and the next under it at the full
width only between two heights a point or so apart; tried from a point
under to a point over the usual (gen.py's), the page fitted alone each
time (page.sh), the value that sets the most of the page's lines where
the scan's are kept, the nearest the usual of those.

    python3 -I feet.py [PAGE...]
"""
import json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.environ.get('PUNCH_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/punch'))
PATH = os.path.join(HERE, 'adjust.json')
TRIES = [0.0, -0.3, 0.3, -0.6, 0.6, -0.9, 0.9, 1.2]


def score(page):
    out = subprocess.run([os.path.join(HERE, 'page.sh'), str(page)], capture_output=True, text=True).stdout
    m = re.findall(r'(\d+) of (\d+) within a point', out)
    return int(m[-1][0]) if m else 0


def main():
    fit = json.load(open(os.path.join(WORK, 'fit.json')))
    pages = [int(a) for a in sys.argv[1:]]
    cuts = [(f['page'], f['cut']) for f in fit if f.get('float') and (not pages or f['page'] in pages)]
    for page, cid in cuts:
        best = None
        for t in TRIES:
            adjust = json.load(open(PATH))
            adjust[f'foot/{cid}'] = t
            json.dump(dict(sorted(adjust.items())), open(PATH, 'w'), indent=0)
            n = score(page)
            if best is None or n > best[0]:
                best = (n, t)
        adjust = json.load(open(PATH))
        adjust[f'foot/{cid}'] = best[1]
        json.dump(dict(sorted(adjust.items())), open(PATH, 'w'), indent=0)
        score(page)
        print(page, cid, best[1], f'{best[0]} lines within a point')


main()
