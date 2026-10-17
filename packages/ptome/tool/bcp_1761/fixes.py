"""bcp.spec from spec.py's draft and what was read off the scan: a line
put right on its page (fixes.tsv: the leaf, the draft's line, the
scan's, ` // ` between lines where one becomes more, nothing where it
goes), a page written whole by hand (pages/LEAF.spec, from its
`@page LEAF PART` line on).

    python3 -I spec.py > bcp.spec.draft && python3 -I fixes.py
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))


def numbered(out):
    """The Psalter's verses numbered in order once more (a line read off
    the scan may have added a verse or taken one away): after a psalm's
    title or a part's of psalm cxix., the initial's verse the first; a
    catchword's number the number of the verse it catches."""
    out, part, n = list(out), None, None
    for k, line in enumerate(out):
        if line.startswith('@page'):
            part = line.split()[2]
        elif part != 'psalter':
            continue
        elif line.startswith('T ') and 'PRAYER' not in line:
            n = 1
        elif line.startswith('P ') and n is not None:
            m = re.match(r'^P \d+ (.*)$', line)
            if m:
                n += 1
                out[k] = f'P {n} {m.group(1)}'
    for k, line in enumerate(out):
        nxt = next((x for x in out[k + 1:] if x[:2] in ('P ', 'I ', '  ', 'T ')), '')
        v = re.match(r'^P (\d+) (\S+)', nxt)
        m = re.search(r'(^f (?:.* \| )?| @ (?:.* \| )?)(\d+)( \S+)$', line)
        if m and v:
            out[k] = line[:m.start(2)] + v.group(1) + line[m.end(2):]
            continue
        m = re.search(r'(^f (?:.* \| )?| @ (?:.* \| )?)(\S+)$', line)
        if m and v and m.group(2) == v.group(2):
            # (The verse's number caught with its first word.)
            out[k] = line[:m.start(2)] + v.group(1) + ' ' + m.group(2)
    return out


LETTERS = 'ABCDEFGHIKLMNOPQRSTVXYZ'
# (Where a gathering starts: its first leaf, the gathering's letters
# counted from there; the octavo's sheets of sixteen pages, signed on
# the rectos of their first four leaves.)
GATHERINGS = ((45, 'B'), (415, 'X'))


def signature(leaf):
    """The signature the printing sets at the foot of [leaf]'s page, or
    None: `X 2`, `A a 3` (a gathering's first leaf its letter alone)."""
    start, letter = max((g for g in GATHERINGS if g[0] <= leaf), default=(None, None))
    if start is None or (leaf - start) % 2 or (leaf - start) % 16 > 6:
        return None
    n = LETTERS.index(letter) + (leaf - start) // 16
    name = LETTERS[n] if n < len(LETTERS) else LETTERS[n - len(LETTERS)] + ' ' + LETTERS[n - len(LETTERS)].lower()
    k = (leaf - start) % 16 // 2 + 1
    return name if k == 1 else f'{name} {k}'


def signed(out):
    """Each foot's signature the one its leaf's place in the book gives
    (Tesseract misreads them), none where the leaf has none."""
    out, leaf = list(out), None
    feet = {}
    for k, line in enumerate(out):
        if line.startswith('@page'):
            leaf = int(line.split()[1])
        elif line.startswith('f ') or ' @ ' in line:
            # (The foot's line: the last, or the one its signature is on.)
            if leaf not in feet or '|' not in out[feet[leaf]].rpartition(' @ ')[2]:
                feet[leaf] = k
    for leaf, k in feet.items():
        line = out[k]
        head, sep, foot = (('f ', '', line[2:]) if line.startswith('f ') else line.partition(' @ '))
        catch = re.split(r'\s*\|\s*', foot)[-1]
        sig = signature(leaf)
        if '|' not in foot and not sig and line.startswith('f '):
            continue
        foot = (sig + ' | ' if sig else '') + catch
        out[k] = ('f ' + foot if line.startswith('f ') else head + ' @ ' + foot).rstrip()
    return out


def main():
    spec = open(os.path.join(HERE, 'bcp.spec.draft'), encoding='utf-8').read().rstrip('\n').split('\n')
    pages, origin, leaf = {}, {}, None
    for i, line in enumerate(spec):
        if line.startswith('@page '):
            leaf = int(line.split()[1])
            pages[leaf], origin[leaf] = [], []
        pages[leaf].append(line)
        origin[leaf].append(i)
    bad = 0
    path = os.path.join(HERE, 'fixes.tsv')
    for n, row in enumerate(open(path, encoding='utf-8') if os.path.exists(path) else [], 1):
        row = row.rstrip('\n')
        if not row or row.startswith('#'):
            continue
        leaf, old, new = row.split('\t')
        lines = pages.get(int(leaf), [])
        if old not in lines:
            print(f'fixes.tsv:{n}: not on page {leaf}: {old}', file=sys.stderr)
            bad += 1
            continue
        k = lines.index(old)
        parts = new.split(' // ') if new else []
        lines[k:k + 1] = parts
        origin[int(leaf)][k:k + 1] = [origin[int(leaf)][k]] * len(parts)
    hand = os.path.join(HERE, 'pages')
    for f in sorted(os.listdir(hand)) if os.path.isdir(hand) else []:
        text = open(os.path.join(hand, f), encoding='utf-8').read().rstrip('\n').split('\n')
        pages[int(text[0].split()[1])] = text
        origin[int(text[0].split()[1])] = [None] * len(text)
    out = signed(numbered([line for leaf in sorted(pages) for line in pages[leaf]]))
    open(os.path.join(HERE, 'bcp.spec'), 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    # (Each line of bcp.spec, the draft's line it comes from: review.py's.)
    sys.path.insert(0, HERE)
    from common import WORK
    json.dump([o for leaf in sorted(pages) for o in origin[leaf]], open(os.path.join(WORK, 'origin.json'), 'w'))
    if bad:
        sys.exit(f'{bad} fixes not applied')


main()
