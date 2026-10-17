"""test/showcase/punch/fetch.yml from cuts.json: each cut the scan's, cut
from the Internet Archive's page image of its leaf (checked by its
SHA-256), its paper whitened and the film's grain gone (`levels`).

    python3 -I fetchyml.py
"""
import hashlib, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.environ.get('PUNCH_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/punch'))
OUT = os.path.join(HERE, '..', '..', 'test', 'showcase', 'punch', 'fetch.yml')
URL = 'https://archive.org/download/sim_punch_1841_1/page/n{leaf}.jpg'


def main():
    cuts = json.load(open(os.path.join(WORK, 'cuts.json')))
    lines = ['# The cuts and the pictorial initials of the three issues, cut from the',
             '# Internet Archive\'s page images of its scan of the first volume',
             '# (sim_punch_1841_1, leaf N the printed page N - 3) where the scan has',
             '# them (tool/punch_1841/cuts.py), fetched by tool/showcase.dart into the',
             '# work cache and checked by the image\'s SHA-256; the paper white, the',
             '# film\'s grain gone (`levels`).']
    sums = {}
    for page in sorted(cuts, key=int):
        leaf = int(page) + 3
        path = os.path.join(WORK, 'jpg', f'n{leaf}.jpg')
        if leaf not in sums:
            sums[leaf] = hashlib.sha256(open(path, 'rb').read()).hexdigest()
        for c in cuts[page]:
            lines += [f"- name: {c['id']}.png", f'  url: {URL.format(leaf=leaf)}', f'  sha256: {sums[leaf]}',
                      '  levels: [60, 190]', f"  crop: [{', '.join(str(v) for v in c['crop'])}]"]
    open(OUT, 'w').write('\n'.join(lines) + '\n')
    print(sum(len(v) for v in cuts.values()), 'cuts')


main()
