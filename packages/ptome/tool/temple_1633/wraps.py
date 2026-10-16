"""Lines of the text the PDF doesn't set whole (wrapped, or set in pieces):
each source line on its page against the PDF page's lines."""
import re, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tfit
L = tfit.pdf_lines()
t = open(os.path.join(os.environ.get('TEMPLE_HERBERT', os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'test', 'showcase', 'herbert')), 'text', 'temple.adoc')).read()
pages = {}; cur = None; other = False
for ln in t.split('\n'):
    m = re.match(r'^// page (\d+) \(leaf (\d+)\)', ln)
    if m:
        cur = int(m[1]); pages[cur] = []; continue
    if ln.startswith('ifndef::backend-pdf'):
        other = True; continue
    if ln.startswith('endif::'):
        other = False; continue
    if other or cur is None or not ln.strip() or re.match(r'^\[[^\]]*\]$', ln) \
            or ln.startswith(('//', 'ifdef', 'image::', "'''", '<<<', '____')):
        continue
    x = re.sub(r'\[\.[^\]]*\]##\{nbsp\}##', '', ln)
    x = re.sub(r'\[\.turn\]#\(([^#]*)#', r' \1', x)
    x = re.sub(r'\[\.[^\]]*\]##([^#]*)##', r'\1 ', x)
    pages[cur].append(tfit.core(x.lstrip('=').strip()))
bad = 0
for p in range(9, 201):
    have = [tfit.core(l['t']) for l in L[p - 1]] + [tfit.core(pc) for l in L[p - 1] for pc in l.get('pieces', [])]
    for s in pages.get(p, []):
        if len(s) < 4 or s in have:
            continue
        # (A drop capital's line: its letter apart.)
        if any(h == s[1:] or h.endswith(s[1:]) and len(s) > 6 for h in have):
            continue
        # (A turned line: its line and its turned word one PDF line.)
        if any(s in h for h in have):
            continue
        bad += 1
        print(p, s[:60])
print(bad, 'lines not set whole')
