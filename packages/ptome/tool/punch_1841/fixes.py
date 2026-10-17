"""punch.spec from spec.py's draft and the corrections read from the
scan: each fix a passage of the draft and what the scan prints there
(fixes.txt: `@@` lines between them, the passage, `--`, its fix); a
passage that is a page's first line, `@page N leaf L`, alone: the page
written whole by hand, the draft's page replaced to the next page's; a
passage of a line, `...`, a line: from the one to the other.

    python3 -I spec.py > punch.spec.draft && python3 -I fixes.py
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    spec = open(os.path.join(HERE, 'punch.spec.draft'), encoding='utf-8').read()
    path = os.path.join(HERE, 'fixes.txt')
    fixes = open(path, encoding='utf-8').read() if os.path.exists(path) else ''
    bad = 0
    blocks = fixes.split('@@\n')[1:]
    for block in blocks:
        old, _, new = block.partition('--\n')
        old = old[:-1] if old.endswith('\n') else old
        new = new[:-1] if new.endswith('\n') else new
        if re.fullmatch(r'@page \d+ leaf \d+', old):
            # (A page written whole: from its first line to the next page's.)
            i = spec.index(old + '\n')
            j = spec.find('\n@page ', i + 1)
            spec = spec[:i] + new + (spec[j:] if j >= 0 else '\n')
            continue
        parts = old.split('\n')
        if len(parts) == 3 and parts[1] == '...':
            # (A passage by its first and last lines, `...` between them; a
            # line ending in `…` by its start.)
            def at(line, start):
                if line.endswith('…'):
                    m = re.compile('^' + re.escape(line[:-1]) + '.*$', re.M).search(spec, start)
                    return (m.start(), m.end()) if m else (-1, -1)
                k = spec.find('\n' + line + '\n', start - 1) if start else spec.find(line + '\n')
                if k < 0:
                    return (-1, -1)
                k = k + 1 if start else k
                return (k, k + len(line))
            i, _ = at(parts[0], 0)
            j0, j1 = at(parts[2], i + 1) if i >= 0 else (-1, -1)
            if i >= 0 and j0 >= 0:
                spec = spec[:i] + new + spec[j1:]
                continue
        if '\n' not in old and old.endswith('…') and old not in spec:
            # (A line by its start, `…` for the rest: a line too long to
            # copy whole.)
            m = re.search('^' + re.escape(old[:-1]) + '.*$', spec, re.M)
            if m:
                spec = spec[:m.start()] + new + spec[m.end():]
                continue
        if old not in spec:
            print('not found:', old.splitlines()[:2], file=sys.stderr)
            bad += 1
            continue
        spec = spec.replace(old, new, 1)
    open(os.path.join(HERE, 'punch.spec'), 'w', encoding='utf-8').write(spec)
    print(f'{len(blocks) - bad} fixes applied; {bad} not found')


main()
