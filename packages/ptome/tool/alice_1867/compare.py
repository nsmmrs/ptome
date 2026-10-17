"""Compare a PDF's pages with the printing's, line by line.

    python3 -I compare.py BOOK PDF [FIRST-PDF-PAGE] [--pages]

The printing's lines are the transcription's (out/BOOK/lines.tsv, each
with its OCR line and so its page and place); the PDF's are Poppler's
(`pdftotext -bbox-layout`). Reports, for each printed page, whether the
PDF page with its number starts and ends with the same words, how many of
its lines differ, and how far its lines sit from the scan's (the first
line's baseline, the line pitch).
"""
import html, json, os, re, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import BOOKS, ROOT, BOOK, DPI, PITCH_PX, ocr_path, scan_path

SCALE = 72 / DPI


def norm(text):
    t = html.unescape(text)
    t = t.replace('­', '-').replace('⁠', '').replace('​', '')
    t = t.translate(str.maketrans({'“': '"', '”': '"', '‘': "'", '’': "'"}))
    t = re.sub(r'\s+', ' ', t).strip()
    t = re.sub(r' (?=[,.;:!?)])', '', t)
    # (Capitals and small capitals read back as capitals; an initial
    # apart from its word.)
    return t.lower().replace(' ', '')


def printed_lines(book):
    """The printing's lines in order: (page, line id, text), each word
    divided where the printing divides it."""
    rows = []
    for row in open(f'{ROOT}/out/{book}/lines.tsv', encoding='utf-8'):
        lid, _, text = row.rstrip('\n').partition('\t')
        rows.append((lid, text))
    cfg = BOOKS[book]
    out = []
    carry = ''
    prev = None
    for lid, text in rows:
        leaf = int(lid.split(':')[0])
        index = lid.split(':')[1]
        # (The rest of a divided word alone on a line the source has none
        # for: a paragraph's last.)
        if carry and prev is not None and '+' not in lid and '+' not in prev[1] \
                and prev[0] == leaf and int(index) > int(prev[1]) + 1:
            out.append((leaf - cfg['offset'], f'{leaf}:{int(prev[1]) + 1}', carry))
            carry = ''
        prev = (leaf, index)
        if lid in BOOKS[book].get('not_compared', ()):
            continue
        text = re.sub(r" '''$", '', text)
        # (A table's delimiters the draft read into the sum's lines, which a
        # patch sets as the printing sets the sum.)
        text = re.sub(r' ?\[cols="1"\] \|===| \|===$', '', text)
        t = re.sub(r'__|\[\.[a-z-]+\]##|##|\[\.[a-z-]+\]#|#|\[\.[a-z-]+\]', '', text)
        t = (carry + ' ' + t).strip() if carry else t
        carry = ''
        words = t.split(' ')
        last = words[-1]
        for mark, shown in (('{shy}', '-'), ('{zwsp}', '')):
            if mark in last:
                head, _, rest = last.rpartition(mark)
                words[-1] = head.replace('{shy}', '').replace('{zwsp}', '') + shown
                carry = rest
                break
        line = ' '.join(words).replace('{shy}', '').replace('{zwsp}', '')
        if book == 'wonderland' and lid == '53:2':
            # (The Mouse's Tale, set by hand: its first line on this one.)
            import tale
            lines = [re.sub(r'__', '', t) for _, _, t in tale.LINES]
            out.append((leaf - cfg['offset'], lid, line + ' ' + lines[0]))
            out.extend((leaf - cfg['offset'], f'tale:{n}', t) for n, t in enumerate(lines[1:], 1))
            continue
        out.append((leaf - cfg['offset'], lid, line))
    # (The lines the transcription sets apart at the end.)
    for lid, role in cfg.get('end_lines', {}).items():
        leaf = int(lid.split(':')[0])
        text = 'THE END.' if role == 'the-end' else 'R. CLAY, SON, AND TAYLOR, PRINTERS, BREAD STREET HILL.'
        out.append((leaf - cfg['offset'], lid, text))
    return out


def pdf_pages(pdf):
    xml = subprocess.run(['pdftotext', '-bbox-layout', pdf, '-'], capture_output=True,
                         text=True).stdout
    pages = []
    for page in re.findall(r'<page [^>]*>(.*?)</page>', xml, re.S):
        lines = []
        for line in re.findall(r'<line xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</line>', page, re.S):
            x0, y0, x1, y1, body = line
            words = re.findall(r'>([^<]*)</word>', body)
            lines.append(dict(x0=float(x0), y0=float(y0), x1=float(x1), y1=float(y1),
                              text=' '.join(words)))
        # (A line's baseline: its box's foot less its descent, a quarter of
        # its type's size, so that words of two sizes on one line, the
        # Gnat's tiny voice after Alice's, are one line.)
        for l in lines:
            l['base'] = l['y1'] - 0.24 * (l['y1'] - l['y0'])
        lines.sort(key=lambda l: (l['base'], l['x0']))
        groups = []
        for l in lines:
            if groups and abs(groups[-1][0]['base'] - l['base']) < 1.5:
                groups[-1].append(l)
            else:
                groups.append([l])
        merged = []
        for g in groups:
            g.sort(key=lambda l: l['x0'])
            m = dict(g[0])
            m['text'] = ' '.join(l['text'] for l in g)
            m['x1'] = max(l['x1'] for l in g)
            m['y0'] = min(l['y0'] for l in g)
            m['y1'] = max(l['y1'] for l in g)
            merged.append(m)
        pages.append(merged)
    return pages


def main():
    book, pdf = sys.argv[1], sys.argv[2]
    first = int(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3].isdigit() else 1
    detail = '--pages' in sys.argv
    printed = printed_lines(book)
    by_page = {}
    for page, lid, text in printed:
        by_page.setdefault(page, []).append((lid, text))
    pages = pdf_pages(pdf)
    ocr = json.load(open(ocr_path(BOOKS[book])))
    good = 0
    total = 0
    bad_lines = 0
    for number in sorted(by_page):
        if number < 1:
            continue  # (the front matter's unnumbered pages)
        want = by_page[number]
        idx = first - 1 + number - 1
        if idx >= len(pages):
            break
        # (The PDF page's text lines: below its running head.)
        have = [l for l in pages[idx] if l['y0'] > 45
                and not re.fullmatch(r'[*\s]+', l['text'])
                # (The printer's signature at the foot.)
                and not (l['y0'] > 424 and re.fullmatch(r'[A-Z]{1,2}( ?[0-9])?', l['text'].strip()))]
        # (Lines in mirror type, read back reversed: not the printing's
        # lines the transcription keeps.)
        mirrored = BOOKS[book].get('mirrored')
        if mirrored:
            have = [l for l in have if not re.search(mirrored, norm(l['text'])[::-1])]
        hv = [norm(l['text']) for l in have]
        wv = [norm(t) for _, t in want]
        # (The page's heading lines, a chapter's, aren't in the printing's
        # body lines: matched past.)
        start = 0
        while start < len(hv) and wv and hv[start] != wv[0] and start < 3:
            start += 1
        if start == 3:
            start = 0
        hv_body = hv[start:]
        total += 1
        same_ends = bool(hv_body) and bool(wv) and hv_body[0] == wv[0] and hv_body[-1] == wv[-1]
        diff = sum(1 for a, b in zip(hv_body, wv) if a != b) + abs(len(hv_body) - len(wv))
        bad_lines += diff
        if same_ends and diff == 0:
            good += 1
        # (The first line's baseline against the scan's: the OCR box's
        # bottom less its descent, roughly.)
        lid0 = want[0][0].split('+')[0]
        leaf, i = (int(x) for x in lid0.split(':'))
        y_scan = ocr[leaf]['lines'][i]['b'][1] * SCALE
        y_pdf = have[start]['y0'] if len(have) > start else 0
        flag = 'ok ' if same_ends and diff == 0 else 'BAD'
        if flag == 'BAD' and len(hv_body) > len(wv) and hv_body[:len(wv)] == wv and wv:
            # (The printing ends this page early, inside a paragraph.)
            print(f'EARLY {want[-1][0]}')
        if f'--show={number}' in sys.argv:
            for a, b in zip(hv_body + [''] * 30, wv + [''] * 30):
                if a or b:
                    print(('   ' if a == b else ' ≠ ') + a[:50].ljust(52) + b[:50])
        if detail or flag == 'BAD':
            print(f'{flag} p.{number:3d} (pdf {idx + 1:3d}) lines {len(hv_body):2d}/{len(wv):2d} '
                  f'differ {diff:2d} top {y_pdf - y_scan:+5.1f}pt | '
                  f'{(hv_body[0] if hv_body else "")[:28]!r} .. {(hv_body[-1] if hv_body else "")[-28:]!r}'
                  f'  want {wv[0][:28]!r} .. {wv[-1][-28:]!r}')
    print(f'{good} of {total} pages match; {bad_lines} lines differ')


if __name__ == '__main__':
    main()
