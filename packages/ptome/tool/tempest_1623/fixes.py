"""folio.spec from spec.py's draft and the corrections read from the
scan: each fix a passage of the draft and what the scan prints there
(fixes.txt: `@@` lines between them, the passage, `--`, its fix); each
page's foot (its signature and catchword); the transcription's
illegible letters (`•`) filled from the scan.

    python3 -I spec.py > folio.spec.draft && python3 -I fixes.py
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
FEET = {1: 'A|(Who', 2: '|Good', 3: 'A 2|Which', 4: '|_Pro._ Thou', 5: 'A 3|_Pro._', 6: '|_Gon._',
        7: '|_Ant._', 8: '|If', 9: '|But', 10: "|He's", 11: '|_Cal._', 12: '|Scena', 13: 'B|_Ant._',
        14: '|_Iuno_', 15: 'B 2|_Ste._ Put', 16: '|Didſt', 17: 'B 3|That', 18: '|And'}

spec = open(os.path.join(HERE, 'folio.spec.draft'), encoding='utf-8').read()
fixes = open(os.path.join(HERE, 'fixes.txt'), encoding='utf-8').read()
bad = 0
for block in fixes.split('@@\n')[1:]:
    old, _, new = block.partition('--\n')
    # (A passage ends where its last line does: a part of a line too.)
    old, new = old[:-1] if old.endswith('\n') else old, new[:-1] if new.endswith('\n') else new
    if old not in spec and old.startswith('@page') and old.split('\n')[0] + '\n' in spec:
        # (A page written whole by hand, from its start to the end: the
        # draft's page, whatever it holds, replaced.)
        spec = spec[:spec.index(old.split('\n')[0] + '\n')] + new
        continue
    if old not in spec:
        print('not found:', old.splitlines()[:2], file=sys.stderr)
        bad += 1
        continue
    spec = spec.replace(old, new, 1)
out, page = [], None
for line in spec.split('\n'):
    if line.startswith('@page'):
        if page in FEET:
            out.append('@foot ' + FEET[page])
        page = int(line.split()[1])
    if line.startswith('# ocr:'):
        continue
    out.append(line)
spec = '\n'.join(out)
left = spec.count('•')
open(os.path.join(HERE, 'folio.spec'), 'w', encoding='utf-8').write(spec)
print(f'{len(fixes.split("@@")) - 1 - bad} fixes applied; {bad} not found; {left} illegible letters left')
