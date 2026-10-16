"""Fit each block's `margin-top` so that the PDF sets it where the
printing does: build the text (build.py), set it (ptome), read where each
fitted block's first line (a picture's top, a rule) is, move its margin
by how far it is off less how far the block before it on its page was
off, again until every block is within a tenth of a point or the passes
run out.

    python3 -I fit.py [PASSES]

This folder holds the specs and margins.json; the PDF is set in the work
folder's staged copy of the work (build/mcguffey, tool/showcase.dart's),
with the work's own look and text copied over it (README.md).
"""
import json, os, re, shutil, subprocess, sys, unicodedata

WORK = os.environ.get('MCG_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match'))
# The specs and margins.json: this folder; the work: the repository's.
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, '..', '..', 'test', 'showcase', 'mcguffey')
STAGE = f'{WORK}/build/mcguffey'
PTOME = f'{WORK}/ptome'
PDF = f'{STAGE}/mcguffey.pdf'
# Where a line's baseline is in Poppler's box for it (its font's ascent
# over its ascent and descent).
RATIO = dict(text=1.1963 / (1.1963 + 0.4395), heading=1.069 / 1.362, script=0.9927 / 1.25)


def core(text):
    t = unicodedata.normalize('NFKD', text)
    # (A cross reference's text.)
    t = re.sub(r'<<[^,>]*,([^>]*)>>', r'\1', t)
    t = re.sub(r'\[\.[^\]]*\]|#|_|pass:\[[^\]]*\]|<[^>]*>|\{[a-z]+\}|<<[^,>]*,', '', t)
    # (A leading numeral aside: a contents' or a list's.)
    return re.sub(r'^[0-9]+', '', re.sub(r'[^a-z0-9]', '', t.lower()))


def build(margins):
    json.dump(margins, open(f'{HERE}/margins.json', 'w'), indent=0, sort_keys=True)
    subprocess.run([sys.executable, '-I', f'{HERE}/build.py', HERE, f'{REPO}/text', f'{HERE}/margins.json'],
                   check=True, stdout=subprocess.DEVNULL)
    shutil.move(f'{REPO}/text/fit.json', f'{HERE}/fit.json')
    for name in ['mcguffey.adoc', 'mcguffey-look.yml']:
        shutil.copy(f'{REPO}/{name}', f'{STAGE}/{name}')
    os.makedirs(f'{STAGE}/text', exist_ok=True)
    for name in os.listdir(f'{REPO}/text'):
        shutil.copy(f'{REPO}/text/{name}', f'{STAGE}/text/{name}')
    r = subprocess.run([PTOME, '-b', 'pdf', '-o', PDF, f'{STAGE}/mcguffey.adoc'],
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
            words = re.findall(r'>([^<]*)</word>', body)
            lines.append(dict(y0=float(y0), y1=float(y1), x0=float(x0), t=' '.join(words)))
        # (The pieces of one line, a table's cells, on one baseline: one
        # line, left to right.)
        lines.sort(key=lambda l: l['y1'])
        groups = []
        for l in lines:
            if groups and abs(groups[-1][0]['y1'] - l['y1']) < 1.0:
                groups[-1].append(l)
            else:
                groups.append([l])
        merged = []
        for group in groups:
            group.sort(key=lambda l: l['x0'])
            first = dict(group[0])
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
        scale = 498.2 / float(height)
        pages.append(sorted(float(t) * scale for t in re.findall(r'<image top="([\d.]+)"', page)))
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


# (The page's body: from the top margin to the foot's.)
BODY = 498.2 - 40.43 - 38


def on_page(fit, lines, images, taken, page):
    if page < 0 or page >= len(lines):
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
    for n, l in enumerate(lines[page]):
        if n in used:
            continue
        haves = [core(re.sub(r'^\s*\d{1,2}\.\s*', '', t)) for t in [l['t']] + l.get('pieces', [])[1:]]
        have = next((h for h in haves[1:] if h == want), haves[0])
        # (A heading whole: LESSON XI. isn't LESSON XII.)
        if fit['kind'] == 'heading' and have != want:
            continue
        k = min(len(want), len(have), 8)
        # (A short line, a title, whole: not the start of a longer.)
        if len(want) < 10 and want != have and fit['kind'] not in ('table', 'heading'):
            continue
        if k >= 3 and want[:k] == have[:k]:
            used.add(n)
            return l['y0'] + (l['y1'] - l['y0']) * RATIO[fit['font']]
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
        taken = {}
        worst = 0.0
        prev_page, prev_err, prev_got = None, 0.0, 0.0
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
            floor = 0.0 if fit['kind'] == 'heading' else -420.0
            margins[key] = round(max(floor, min(200.0, margin + step)), 2)
            worst = max(worst, abs(err))
            prev_page, prev_err = fit['page'], err
        print(f'pass {n + 1}: worst {worst:.2f} pt, fitted through page {stop_page}, '
              f'{len(missing)} not found' + (f' ({missing[0]})' if missing else ''))
        json.dump(fits, open(f'{HERE}/fit-result.json', 'w'), ensure_ascii=False, indent=1)
        json.dump(state, open(state_path, 'w'), indent=0)
        if worst < 0.1 and not missing:
            break
        # (No further for passes: a page that won't come right says so.)
        sig = (stop_page, len(missing))
        same = same + 1 if sig == last else 0
        last = sig
        if same >= 25:
            print('  stuck: ' + '; '.join(missing[:5]))
            break
    json.dump(margins, open(path, 'w'), indent=0, sort_keys=True)
    build(margins)


if __name__ == '__main__':
    main(*map(int, sys.argv[1:]))
