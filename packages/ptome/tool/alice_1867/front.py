"""The 1867 title page and contents as PDF-only blocks, each line placed
where the printing places it: sizes from the letters' heights on the
scan, letter-spacing from the lines' widths, margins from the baselines,
corrected against the PDF (built, measured, built again) until each
baseline is within a fifth of a point.

    python3 -I front.py
"""
import json, os, re, subprocess, sys
from fontTools.ttLib import TTFont
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import ROOT, BOOK, DPI, PITCH_PX

REPO = os.path.dirname(os.path.dirname(HERE))  # packages/ptome
WORK = os.path.join(REPO, 'test', 'showcase', 'alice')
FONTS = os.environ.get('PTOME_FONTS', os.path.expanduser('~/.local/share/fonts/ptome'))
_faces = {}


def advance(text, style='Regular', size=10.0, smallcaps=False):
    if style not in _faces:
        f = TTFont(f'{FONTS}/OldStandardTT-{style}.ttf')
        _faces[style] = (f.getBestCmap(), f['hmtx'])
    cmap, hmtx = _faces[style]
    w = 0.0
    for ch in text:
        s = size
        if smallcaps and ch.islower():
            ch, s = ch.upper(), size * 0.8
        g = cmap.get(ord(ch))
        w += (hmtx[g][0] if g else 500) / 1000 * s
    return w


# The title page (leaf 9: its scan's own scale, its height the page's).
S = 449.7 / 4386
TITLE = [
    # role, text, OCR top px, cap px, x0, x1 (px), style, smallcaps
    ('tp-title', 'ALICE’S ADVENTURES', 318, 118, 242, 2310, 'Regular', False),
    ('tp-title', 'IN WONDERLAND.', 738, 116, 440, 2134, 'Regular', False),
    ('tp-by', 'BY', 1403, 30, 1255, 1335, 'Regular', False),
    ('tp-author', 'LEWIS CARROLL.', 1528, 71, 802, 1769, 'Regular', False),
    ('tp-italic', 'WITH FORTY-TWO ILLUSTRATIONS', 2178, 54, 506, 2053, 'Italic', False),
    ('tp-italic', 'BY JOHN TENNIEL.', 2349, 50, 843, 1706, 'Italic', False),
    ('tp-edition', 'SIXTH THOUSAND.', 2926, 44, 1001, 1558, 'Regular', False),
    ('tp-place', 'London:', 3474, 62, 1127, 1414, None, False),
    ('tp-publisher', 'MACMILLAN AND CO.', 3612, 64, 596, 1956, 'Regular', False),
    ('tp-year', '1867.', 3755, 59, 1183, 1361, 'Regular', False),
    ('tp-rights', '{startsb}__The Right of Translation and Reproduction is reserved.__{endsb}', 4220, 52, 422, 2101, 'Italic', False),
]
CAP = 0.712


def title_page(fit, wants=None):
    out = ['// The title page as the 1867 printing sets it (front.py, from the',
           '// scan): each line its size, its letter-spacing, its place.']
    roles = {}
    prev = None
    for n, (role, text, top, cap, x0, x1, style, sc) in enumerate(TITLE):
        size = round(cap * S / CAP, 2)
        base = (top + cap) * S if wants is None else wants[n]
        plain = re.sub(r'__|\{startsb\}|\{endsb\}', '', text)
        natural = advance(plain, style or 'Regular', size, sc)
        width = (x1 - x0) * S
        track = 0 if style is None else max(0.0, (width - natural) / max(1, len(plain) - 1))
        roles.setdefault(role, (size, track, style))
        margin = fit.get(n, 0.0) + (base if prev is None else base - prev)
        if prev is None:
            # (The page's first: a spacer above it, a page's top margin
            # dropped.)
            out += ['', f'image::blank.svg["",role=cut,pdfwidth=1pt,pdfheight={margin - 12:.2f}pt]',
                    '', f'[.{role},margin-top=0,margin-bottom=0]', text]
        else:
            out += ['', f'[.{role},margin-top={margin:.2f}pt,margin-bottom=0]', text]
        prev = base
    return '\n'.join(out) + '\n', roles


# The contents (leaf 15, the text pages' scale).
PT = 72 / DPI
CONTENTS_TOP = (782, 80)
LABELS = (1133, 39)
ENTRIES = [('I.', 'down the rabbit-hole', 1), ('II.', 'the pool of tears', 15),
           ('III.', 'a caucus-race and a long tale', 29),
           ('IV.', 'the rabbit sends in a little bill', 41),
           ('V.', 'advice from a caterpillar', 59), ('VI.', 'pig and pepper', 67),
           ('VII.', 'a mad tea-party', 95), ('VIII.', 'the queen’s croquet-ground', 112),
           ('IX.', 'the mock turtle’s story', 130), ('X.', 'the lobster quadrille', 147),
           ('XI.', 'who stole the tarts?', 162), ('XII.', 'alice’s evidence', 176)]
ENTRY_TOPS = [1260, 1450, 1646, 1841, 2033, 2226, 2423, 2618, 2815, 3008, 3202, 3395]
ENTRY_SIZE = 8.0
MEASURE = 250.1


def contents(fit, dots_fit):
    out = ['// The contents as the 1867 printing sets them (front.py): the',
           '// chapters\' numerals in a column, their titles in small capitals,',
           '// dotted to the pages.']
    head_size = round(CONTENTS_TOP[1] * PT / CAP, 2)
    base = (CONTENTS_TOP[0] + CONTENTS_TOP[1]) * PT
    out += ['', f'image::blank.svg["",role=cut,pdfwidth=1pt,pdfheight={fit.get("title", 0) + base - 12:.2f}pt]',
            '', '[.toc-title,margin-top=0,margin-bottom=0]', 'CONTENTS.']
    prev = base
    lb = (LABELS[0] + LABELS[1]) * PT
    out += ['', f'[.toc-labels,margin-top={fit.get("labels", 0) + lb - prev:.2f}pt,margin-bottom=0]',
            '[.toc-chapter]#chapter# [.toc-page]#page#']
    prev = lb
    num_w = 26.0
    for i, ((num, title, page), top) in enumerate(zip(ENTRIES, ENTRY_TOPS)):
        b = (top + 52) * PT
        used = advance(title, 'Regular', ENTRY_SIZE, True) + advance(f'{page}', 'Regular', ENTRY_SIZE)
        unit = advance(' .', 'Regular', ENTRY_SIZE)
        room = MEASURE - num_w - used - 2 * advance(' ', 'Regular', ENTRY_SIZE)
        dots = max(0, int(room / unit) + dots_fit.get(i, 0))
        out += ['', f'[.toc-entry,margin-top={fit.get(i, 0) + b - prev:.2f}pt,margin-bottom=0]',
                f'pass:[<font width="{num_w}pt">{num}</font>][.sc]#{title}#' + ' .' * dots +
                f' [.toc-pg]#{page}#']
        prev = b
    return '\n'.join(out) + '\n', head_size


def build():
    out = f'{ROOT}/front-check.pdf'
    cmd = ['dart', 'run', 'bin/ptome.dart', '-b', 'pdf',
           '-a', f'imagesdir={ROOT}/build/alice/images', f'{WORK}/alice.adoc', '-o', out]
    r = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True)
    if r.returncode:
        raise SystemExit(r.stdout + r.stderr)
    return out


def lines_of(pdf, page):
    xml = subprocess.run(['pdftotext', '-f', str(page), '-l', str(page), '-bbox-layout', pdf, '-'],
                         capture_output=True, text=True).stdout
    found = []
    for m in re.finditer(r'<line xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</line>', xml, re.S):
        words = ' '.join(re.findall(r'>([^<]*)</word>', m.group(5)))
        found.append((float(m.group(2)), float(m.group(4)), float(m.group(1)), float(m.group(3)), words))
    return found


def find_page(pdf, needle):
    n = int(re.search(r'Pages:\s+(\d+)', subprocess.run(['pdfinfo', pdf], capture_output=True,
                                                        text=True).stdout).group(1))
    for page in range(1, min(n, 30) + 1):
        text = subprocess.run(['pdftotext', '-f', str(page), '-l', str(page), pdf, '-'],
                              capture_output=True, text=True).stdout
        if needle in text:
            return page
    raise SystemExit(f'no page with {needle!r}')


def main():
    if '--roles' in sys.argv:
        _, roles = title_page({})
        for role, (size, track, style) in roles.items():
            print(f'{role}: size {size} tracking {track:.2f}pt style {style}')
        _, head = contents({}, {})
        print('toc-title size', head)
        return
    # (One render with no margins, each line straight under the one before:
    # how far apart each two lines are set by themselves; then the margins
    # that make up the printing's distances; then a render to check.)
    def render(tp_margins, c_margins, dots):
        tp, _ = title_page(tp_margins, tp_wants)
        open(f'{WORK}/text/wonderland/title-page.adoc', 'w', encoding='utf-8').write(tp)
        ct, _ = contents(c_margins, dots)
        open(f'{WORK}/text/wonderland/contents.adoc', 'w', encoding='utf-8').write(ct)
        pdf = build()
        tp_page = find_page(pdf, 'SIXTH')
        c_page = find_page(pdf, 'CONTENTS')
        return pdf, lines_of(pdf, tp_page), lines_of(pdf, c_page)

    def base(g):
        return g[1] - 0.238 * (g[1] - g[0])

    def tp_baselines(lines):
        # (In order down the page, below the running head's place.)
        rows = sorted((g for g in lines if g[0] > 45), key=lambda g: g[0])
        merged = []
        for g in rows:
            if merged and abs(base(merged[-1]) - base(g)) < 1:
                continue
            merged.append(g)
        out = [base(g) for g in merged][:len(TITLE)]
        return out + [None] * (len(TITLE) - len(out))

    def c_baselines(lines):
        title = next((base(g) for g in lines if 'CONTENTS' in g[4]), None)
        labels = next((base(g) for g in lines if g[2] < 20 and 'CHAPTER' in g[4].upper()
                       and g[0] > 45), None)
        nums = sorted((g for g in lines if g[2] < 42 and re.match(r'[IVX]+\.( |$)', g[4].strip())),
                      key=lambda g: g[0])
        out = [title, labels] + [base(g) for g in nums][:len(ENTRIES)]
        return out + [None] * (2 + len(ENTRIES) - len(out))

    tp_needles = [re.sub(r'__|\[|\]', '', t[1]).split()[0].lower().replace('’', "'") for t in TITLE]
    # (The title leaf's lines run from above the text pages' text area to
    # below it: its gaps closed in proportion, the lines their own sizes,
    # from the text area's top to its foot.)
    raw = [(t[2] + t[3]) * S for t in TITLE]
    first, last = 68.5, 422.3 - 0.238 * 7.49 - 1.5
    k = (last - first) / (raw[-1] - raw[0])
    tp_wants = [first + (w - raw[0]) * k for w in raw]
    c_keys = ['title', 'labels'] + list(range(len(ENTRIES)))
    c_needles = ['contents', 'chapter'] + [' '.join(e[1].split()[:2]).replace('’', "'") for e in ENTRIES]
    c_wants = [sum(CONTENTS_TOP) * PT, sum(LABELS) * PT] + [(t + 52) * PT for t in ENTRY_TOPS]

    def zero(keys, wants):
        # margins (a fit of -want+...): each margin 0, the first's spacer 12 pt
        fit = {}
        prev = None
        for k, w in zip(keys, wants):
            fit[k] = -w + 12 if prev is None else -(w - prev)
            prev = w
        return fit

    fit_tp = zero(range(len(TITLE)), tp_wants)
    fit_c = zero(c_keys, c_wants)
    dots = {}
    pdf, tp_lines, c_lines = render(fit_tp, fit_c, dots)
    for fit, keys, wants, got in (
            (fit_tp, list(range(len(TITLE))), tp_wants, tp_baselines(tp_lines)),
            (fit_c, c_keys, c_wants, c_baselines(c_lines))):
        prev_got = prev_want = None
        for k, w, g in zip(keys, wants, got):
            if g is None:
                print('not found:', k)
                continue
            if prev_got is None:
                # the first: no spacer (its margin 12), its baseline then g;
                # its margin w - g + 12, its fit that less w
                fit[k] = 12 - g
            else:
                fit[k] = (w - prev_want) - (g - prev_got) - (w - prev_want)
            prev_got, prev_want = g, w
    # (fit is added to the wanted distance: margin = distance + fit; then
    # rounds of corrections, each line's error less the one before's.)
    for rounds in range(4):
        pdf, tp_lines, c_lines = render(fit_tp, fit_c, dots)
        worst = 0.0
        for name, fit, keys, got, wants in (
                ('title', fit_tp, list(range(len(TITLE))), tp_baselines(tp_lines), tp_wants),
                ('contents', fit_c, c_keys, c_baselines(c_lines), c_wants)):
            errs = [None if g is None else w - g for w, g in zip(wants, got)]
            print(f'round {rounds} {name} errors:', ' '.join('--' if e is None else f'{e:+.1f}' for e in errs))
            prev = 0.0
            for k, e in zip(keys, errs):
                if e is None:
                    worst = max(worst, 99)
                    continue
                worst = max(worst, abs(e))
                fit[k] += e - prev
                prev = e
        if worst < 0.25:
            break


if __name__ == '__main__':
    main()
