"""Each page's text baselines in the PDF against those gen.py set: a
line broken, or one out of place by more than a point, reported.

    python3 -I check.py PDF EXPECT-JSON
"""
import json, re, subprocess, sys


def main():
    pdf, exp = sys.argv[1], json.load(open(sys.argv[2]))
    xml = subprocess.run(['pdftotext', '-bbox', pdf, '-'], capture_output=True, text=True, check=True).stdout
    pages = xml.split('<page ')[1:]
    bad = 0
    for i, leaf in enumerate(sorted(exp, key=int)):
        words = re.findall(r'yMax="([\d.]+)">([^<]*)<', pages[i])
        # (A signature, a capital in a small size, its descent its own.)
        bases = sorted({round(float(y), 0) for y, w in words if float(y) > 40 and re.search(r"\w", w) and not re.fullmatch(r"[A-Z]", w)})
        # (A word's box bottom is its descent below the baseline: the
        # text's, 10.6 pt Caslon's, about 2.9 pt.)
        got = []
        for b in bases:
            if not got or b - got[-1] > 3:
                got.append(b)
        want = [b for b in exp[leaf]]
        extra = [g for g in got if not any(abs(g - 2.9 - w) < 3.5 for w in want)]
        if extra:
            bad += 1
            print(leaf, 'lines not set:', extra[:6])
    print('pages with stray lines:', bad)


if __name__ == '__main__':
    main()
