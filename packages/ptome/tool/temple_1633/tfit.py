"""Fit each block's `margin-top` so that the PDF sets it where the
printing does: build the text (build.py), set it (ptome), read where each
fitted block's first line (a picture's top, a rule) is, move its margin
by how far it is off less how far the block before it on its page was
off, again until every block is within a tenth of a point or the passes
run out.

    python3 -I fit.py [PASSES]

The work folder's mcg/ holds the specs and margins.json; the PDF is set
in the staged copy of the work (build/mcguffey, tool/showcase.dart's),
with the work's own look and text copied over it.
"""
import difflib, html, json, os, re, shutil, subprocess, sys, unicodedata

WORK = os.environ.get('TEMPLE_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match'))
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(os.environ.get('TEMPLE_HERBERT', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'test', 'showcase', 'herbert')))
STAGE = f'{WORK}/build/herbert'
PTOME = f'{WORK}/ptome'
PDF = f'{STAGE}/herbert.pdf'
# Where a line's baseline is in Poppler's box for it (its font's ascent
# over its ascent and descent).
RATIO = dict(text=0.912 / 1.25, heading=0.912 / 1.25, script=0.912 / 1.25)


def core(text):
    t = unicodedata.normalize('NFKD', text)
    # (A cross reference's text.)
    t = re.sub(r'<<[^,>]*,([^>]*)>>', r'\1', t)
    t = re.sub(r'\[\.[^\]]*\]|#|_|pass:\[[^\]]*\]|<[^>]*>|\{[a-z]+\}|<<[^,>]*,', '', t)
    # (A leading numeral aside: a contents' or a list's.)
    return re.sub(r'^[0-9]+', '', re.sub(r'[^a-z0-9]', '', t.lower()))


def build(margins):
    json.dump(margins, open(f'{HERE}/margins.json', 'w'), indent=0, sort_keys=True)
    subprocess.run([sys.executable, '-I', f'{HERE}/gen.py', f'{REPO}/text', f'{HERE}/margins.json'],
                   check=True, stdout=subprocess.DEVNULL)
    shutil.move(f'{REPO}/text/fit.json', f'{HERE}/fit.json')
    for name in ['herbert.adoc', 'herbert-look.yml']:
        shutil.copy(f'{REPO}/{name}', f'{STAGE}/{name}')
    os.makedirs(f'{STAGE}/text', exist_ok=True)
    for name in os.listdir(f'{REPO}/text'):
        if name.endswith('.adoc'):
            shutil.copy(f'{REPO}/text/{name}', f'{STAGE}/text/{name}')
    r = subprocess.run([PTOME, '-b', 'pdf', '-o', PDF, f'{STAGE}/herbert.adoc'],
                       capture_output=True, text=True)
    if r.returncode != 0 or r.stderr.strip():
        print(r.stderr.strip()[:2000])


def pdf_lines():
    xml = subprocess.run(['pdftotext', '-bbox-layout', PDF, '-'], capture_output=True, text=True).stdout
    pages = []
    for page in re.findall(r'<page [^>]*>(.*?)</page>', xml, re.S):
        lines = []
        for x0, y0, x1, y1, body in re.findall(
                r'<line xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)</line>', page, re.S):
            ws = [(float(a), float(b), float(c), float(d), html.unescape(t)) for a, b, c, d, t in re.findall(
                r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">([^<]*)</word>', body)]
            if not ws:
                continue
            # (The line's box its words' but a drop capital's, taller.)
            hs = sorted(w[3] - w[1] for w in ws)
            h = hs[len(hs) // 2] if len(hs) > 2 else hs[0]
            core_ws = [w for w in ws if w[3] - w[1] <= 1.4 * h] or ws
            if len(ws) == 2 and len(ws[0][4]) == 1 and ws[0][3] - ws[0][1] > 1.4 * (ws[1][3] - ws[1][1]):
                core_ws = [ws[1]]
            lines.append(dict(y0=min(w[1] for w in core_ws), y1=max(w[3] for w in core_ws),
                              x0=float(x0), x1=float(x1), t=' '.join(w[4] for w in ws)))
        # (The pieces of one line, a table's cells, on one baseline: one
        # line, left to right.)
        lines.sort(key=lambda l: l['y1'])
        groups = []
        for l in lines:
            # (One baseline, side by side: not one block's line over
            # another's.)
            if groups and abs(groups[-1][0]['y1'] - l['y1']) < 1.0 and all(
                    l['x0'] >= g['x1'] - 1 or l['x1'] <= g['x0'] + 1 for g in groups[-1]):
                groups[-1].append(l)
            else:
                groups.append([l])
        merged = []
        for group in groups:
            group.sort(key=lambda l: l['x0'])
            # (The line's place its longest piece's: not a drop capital's.)
            first = dict(max(group, key=lambda l: len(l['t'])))
            first['t'] = ' '.join(l['t'] for l in group)
            first['pieces'] = [l['t'] for l in group]
            merged.append(first)
        pages.append(merged)
    return pages


def pdf_images():
    out = f'{WORK}/tmp-fit'
    os.makedirs(out, exist_ok=True)
    subprocess.run(['pdftohtml', '-xml', '-q', '-zoom', '3', PDF, f'{out}/x'], capture_output=True)
    xml = open(f'{out}/x.xml', encoding='utf-8', errors='replace').read()
    pages = []
    for height, page in re.findall(r'<page [^>]*height="([\d.]+)"[^>]*>(.*?)</page>', xml, re.S):
        scale = 422 / float(height)
        pages.append(sorted(float(t) * scale for t in re.findall(r'<image top="([\d.]+)"', page)))
    return pages


def pdf_rules():
    """Each page's rules' tops (points): rows of the page, rasterized,
    dark in one run over most of a rule's width, no more than 2 pt deep."""
    import numpy as np
    from PIL import Image
    out = f'{WORK}/tmp-fit'
    for f in os.listdir(out):
        if f.startswith('r-'):
            os.remove(f'{out}/{f}')
    subprocess.run(['pdftoppm', '-r', '144', '-gray', PDF, f'{out}/r'], check=True)
    pages = []
    for f in sorted(x for x in os.listdir(out) if x.startswith('r-')):
        g = 255 - np.asarray(Image.open(f'{out}/{f}')).astype(float)
        a = g > 127
        rows = []
        for y in range(a.shape[0]):
            row = a[y]
            if row.sum() < 250:
                continue
            e = np.diff(np.concatenate([[0], row.astype(np.int8), [0]]))
            if (np.nonzero(e == -1)[0] - np.nonzero(e == 1)[0]).max() >= 250:
                rows.append(y)
        tops = []
        for y in rows:
            if not tops or y > tops[-1][1] + 1:
                tops.append([y, y])
            else:
                tops[-1][1] = y
        # (Its centre line: the rows' darkness weighed, a pixel each side.)
        centres = []
        for y0, y1 in tops:
            if y1 - y0 > 4:
                continue
            ys = np.arange(max(0, y0 - 1), y1 + 2)
            w = g[ys].sum(1)
            centres.append(float((ys * w).sum() / w.sum()) / 2 + 0.25)
        pages.append(centres)
    return pages


def actual(fit, lines, images, taken):
    """Where [fit]'s block is on its page; on the page after (before), as
    far below (above) it as the page's body is tall; or None."""
    got = on_page(fit, lines, images, taken, fit['page'] - 1)
    if got is not None:
        return got, False
    for shift, body in ((1, BODY), (-1, -BODY)):
        got = on_page(fit, lines, images, {}, fit['page'] - 1 + shift)
        if got is not None:
            return got + body, True
    return None, False


RULES = []
PITCH_OF = {}
# (The page's body: from the top margin to the foot's.)
BODY = 422 - 32


def on_page(fit, lines, images, taken, page):
    if page < 0 or page >= len(lines):
        return None
    if fit['kind'] == 'rule':
        k = taken.setdefault(('rule', page), 0)
        taken[('rule', page)] = k + 1
        return RULES[page][k] if k < len(RULES[page]) else None
    if fit['kind'] in ('letter', 'column'):
        # (A block of an index's column, its letter or its titles: the
        # piece of a line (Poppler reads the two columns' lines on one
        # baseline as one) that starts with its first words, in its
        # column; not the same piece twice.)
        def flat(t):
            return re.sub(r'[^a-z0-9]', '', unicodedata.normalize('NFKD', t).lower())
        want = flat(fit['first'])[:10]
        used = taken.setdefault(('piece', page), set())
        left = fit.get('column', 0) == 0
        for n, l in enumerate(lines[page]):
            for pi, piece in enumerate(l.get('pieces', [l['t']])):
                if (n, pi) in used:
                    continue
                c = flat(piece)
                if fit['kind'] == 'letter':
                    ok = piece.strip() == fit['first']
                else:
                    # (A page number Poppler read with the other column's
                    # first words: past it.)
                    c2 = re.sub(r'^[0-9]+', '', c)
                    # (A drop's line, its first word's rest apart: `He`.)
                    w0 = flat(fit['first'].split()[0]) if fit['first'].split() else ''
                    rest = flat(fit['first'])[len(w0):][:10]
                    ok = c.startswith(want) or c[1:].startswith(want) or (c2 != c and c2.startswith(want)) \
                        or (fit['kind'] == 'column' and 0 < len(w0) <= 3 and len(rest) >= 5 and c.startswith(rest))
                if ok:
                    used.add((n, pi))
                    return l['y0'] + (l['y1'] - l['y0']) * RATIO['text']
        return None
    if fit['kind'] == 'foot':
        # (The foot line: the last line with its words at its end, the
        # signature beside them.)
        want = core(fit['first'])
        for l in reversed(lines[page]):
            if core(l['t']).endswith(want) and l['y0'] >= taken.get(('y', page), -1e9) - 2:
                return l['y0'] + (l['y1'] - l['y0']) * RATIO['text']
        return None
    if fit['kind'] == 'image':
        k = taken.setdefault(('img', page), 0)
        taken[('img', page)] = k + 1
        return images[page][k] if k < len(images[page]) else None
    want = core(fit['first'])
    if fit['kind'] == 'heading':
        want = core(re.sub(r'^== ', '', fit['first']))
    if not want:
        return None
    used = taken.setdefault(('line', page), set())
    # (Below the block before it on the page: a line a poem repeats is
    # this block's where it comes after the last.)
    floor = taken.get(('y', page), -1e9)
    for n, l in enumerate(lines[page]):
        if n in used or l['y0'] < floor - 2:
            continue
        haves = [core(re.sub(r'^\s*\d{1,2}\.\s*', '', t)) for t in [l['t']] + l.get('pieces', [])[1:]]
        have = next((h for h in haves[1:] if h == want), haves[0])
        # (A heading whole: LESSON XI. isn't LESSON XII.)
        if fit['kind'] == 'heading' and have != want:
            continue
        if fit['kind'] == 'heading' and have == want:
            used.add(n)
            taken[('y', page)] = l['y0']
            return l['y0'] + (l['y1'] - l['y0']) * RATIO[fit.get('font', 'text')]
        # (A line beside a drop capital: Poppler may read the capital
        # into it.)
        if want and have[1:1 + 12] == want[:12] and have[:12] != want[:12]:
            have = have[1:]
        # (Poppler may read a word of the line below beside a drop into
        # this one: the line's words found within it.)
        if len(want) >= 14 and want[:14] in have and not have.startswith(want[:14]):
            have = have[have.index(want[:14]):]
        # (A drop's line whose first words Poppler read with the line
        # below: its text from the words after them.)
        if len(have) >= 8 and 0 < want.find(have[:12]) <= 10:
            have = want[:want.find(have[:12])] + have
        k = min(len(want), len(have), 16)
        # (A short line, a title, whole: not the start of a longer.)
        if len(want) < 10 and want != have and fit['kind'] not in ('table', 'heading'):
            continue
        if k >= 3 and want[:k] == have[:k]:
            # (Its second line next, where it has one: a line a poem
            # repeats is the block's only where the next follows it.)
            if fit.get('second'):
                nxt = [x for x in lines[page] if l['y0'] + 5 < x['y0'] < l['y0'] + 14
                       # (or read with a drop beside both, as tall as two)
                       or (x is not l and abs(x['y0'] - l['y0']) < 3 and x['y1'] - x['y0'] > 13)]
                sec = core(fit['second'])[:10]
                full = core(fit['second'])
                if sec and (nxt or l['y0'] < 380) and not any(
                        core(x['t'])[:10] == sec or core(x['t'])[1:11] == sec
                        or any(len(core(x['t'])) >= k + 8 and core(x['t'])[k:k + 8] in full for k in range(4))
                        or (len(full) >= 10 and full[:10] in core(x['t']))
                        # (its words read in among a drop's, out of order)
                        or (len(full) >= 12 and difflib.SequenceMatcher(None, full, core(x['t'])).ratio() > 0.75)
                        for x in nxt):
                    continue
            used.add(n)
            taken[('y', page)] = l['y0']
            # (A line Poppler read with the line below it, beside a drop:
            # its place from its second line's, a line above.)
            if l['y1'] - l['y0'] > 13 and fit.get('second'):
                sec = core(fit['second'])[:10]
                for x in lines[page]:
                    if core(x['t'])[:10] == sec and 5 < x['y0'] - l['y0'] < 16 and x['y1'] - x['y0'] < 13:
                        return x['y0'] + (x['y1'] - x['y0']) * RATIO['text'] - 9.62
            return l['y0'] + (l['y1'] - l['y0']) * RATIO[fit.get('font', 'text')]
    # (A drop's first line Poppler read into pieces past finding: its place
    # from its second line's, found within a line, a line above it.)
    if fit['kind'] == 'text' and fit.get('second') and len(core(fit['second'])) >= 12:
        sec = core(fit['second'])[:12]
        for n, x in enumerate(lines[page]):
            if n in used or x['y0'] < floor - 2 or x['y1'] - x['y0'] > 13:
                continue
            cx = core(x['t'])
            if sec in cx[:20] or (len(cx) >= 8 and cx in core(fit['second'])):
                used.add(n)
                taken[('y', page)] = x['y0'] - 9.62
                return x['y0'] + (x['y1'] - x['y0']) * RATIO['text'] - PITCH_OF.get(fit['key'], 9.62)
    return None


def main(passes=6):
    path = f'{HERE}/margins.json'
    margins = json.load(open(path)) if os.path.exists(path) else {}
    state_path = f'{HERE}/fit-state.json'
    state = json.load(open(state_path)) if os.path.exists(state_path) else {}
    last, same = None, 0
    for n in range(passes):
        build(margins)
        fits = json.load(open(f'{HERE}/fit.json'))
        lines, images = pdf_lines(), pdf_images()
        RULES[:] = pdf_rules()
        taken = {}
        worst = 0.0
        prev_page, prev_err, prev_got, prev_kind = None, 0.0, 0.0, None
        missing = []
        # (Page by page: past the first block not on its page, the pages
        # after are another layout's, left for the next pass.)
        stop_page = None
        for fit in fits:
            key = fit['key']
            if stop_page is not None and fit['page'] > stop_page:
                break
            got, off = actual(fit, lines, images, taken)
            if got is None or off:
                missing.append(f"{key} p.{fit['page']} {fit['first'][:30]!r}")
                stop_page = fit['page']
            if got is None:
                continue
            err = fit['target'] - got
            fit['err'] = err
            margin = margins.get(key, 0.0)
            step = err - (prev_err if prev_page == fit['page'] else 0.0)
            # (A step at a time: a page set out of its place moves the
            # pages after it.)
            step = max(-60.0, min(60.0, step))
            # (Half a large one: a block moving between two pages comes to
            # rest rather than swinging.)
            if abs(step) > 8:
                step /= 2
            # (A heading's margin no less than none: its place is the block
            # before it's to give.)
            floor = -60.0 if fit['kind'] == 'heading' else -420.0
            margins[key] = round(max(floor, min(200.0, margin + step)), 2)
            # (A rule found to the rasterized page's quarter point.)
            worst = max(worst, abs(err) - (0.4 if fit['kind'] in ('rule', 'image') else 0.0))
            prev_page, prev_err, prev_kind = fit['page'], err, fit['kind']
        print(f'pass {n + 1}: worst {worst:.2f} pt, fitted through page {stop_page}, '
              f'{len(missing)} not found' + (f' ({missing[0]})' if missing else ''))
        json.dump(fits, open(f'{HERE}/fit-result.json', 'w'), ensure_ascii=False, indent=1)
        json.dump(state, open(state_path, 'w'), indent=0)
        if worst < 0.1 and not missing:
            break
        # (No further for passes: a page that won't come right says so.)
        sig = (stop_page, len(missing), round(worst, 1))
        same = same + 1 if sig == last else 0
        last = sig
        if same >= 25:
            print('  stuck: ' + '; '.join(missing[:5]))
            break
    json.dump(margins, open(path, 'w'), indent=0, sort_keys=True)
    build(margins)


if __name__ == '__main__':
    main(*map(int, sys.argv[1:]))
