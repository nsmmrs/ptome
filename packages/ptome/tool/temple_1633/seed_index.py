"""Seed the index pages' margins: each block's margin from its target
less the block before it's last line's (the fitter refines them)."""
import json, os, re
fits = json.load(open('fit.json'))
m = json.load(open('margins.json'))
t = open(os.path.join(os.environ.get('TEMPLE_HERBERT', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'test', 'showcase', 'herbert')), 'text', 'temple.adoc')).read().split('\n')
counts = []
i = next(k for k, l in enumerate(t) if l.startswith('// page 201 '))
fits = [f for f in fits if f['page'] >= 201]
while i < len(t):
    l = t[i]
    if re.match(r'^\[.*margin-top=(-?[0-9.]+)pt\]$', l) and 'foot-sig' not in l:
        j = i + 1; n = 0
        while j < len(t) and t[j].strip() and not re.match(r'^\[[^\]]*\]$', t[j]) and not t[j].startswith('endif'):
            n += 1; j += 1
        counts.append((l, n)); i = j; continue
    i += 1
assert len(counts) == len(fits), (len(counts), len(fits))
prev = None
for f, (attr, n) in zip(fits, counts):
    if f['page'] >= 201 and prev and prev[0]['page'] == f['page'] and f['kind'] in ('letter', 'column') \
            and prev[0]['kind'] in ('letter', 'column', 'text'):
        bottom = prev[0]['target'] + (prev[1] - 1) * 9.62 + 2.6
        m[f['key']] = round(f['target'] - 7.0 - bottom, 2)
    prev = (f, n)
json.dump(m, open('margins.json', 'w'), indent=0, sort_keys=True)
print('seeded')
