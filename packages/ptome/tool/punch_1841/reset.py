"""A page's fitted margins forgotten (adjust.json's `top/PAGE/…`), to fit
it again from the look's: after its spec changed.

    python3 -I reset.py PAGE...
"""
import json, os, sys

PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'adjust.json')
pages = sys.argv[1:]
adjust = json.load(open(PATH))
keep = {k: v for k, v in adjust.items() if not any(k.startswith(f'top/{p}/') for p in pages)}
json.dump(keep, open(PATH, 'w'), indent=0)
print(len(adjust) - len(keep), 'margins forgotten')
