"""Each block's space above it (adjust.json's `top/PAGE/REGION/LINE`,
gen.py's, keyed by its first line): its first line's baseline on the PDF
against the scan's (scan.json), its margin moved by its error less what
the blocks above it in its region are moved already; a few rounds, the
pages built each (build.sh).

    python3 -I margins.py [ROUNDS] [PAGE/REGION...]
"""
import json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ARGS = sys.argv[1:]
ROUNDS = int(ARGS[0]) if ARGS else 2
ONLY = set(ARGS[1:]) or None
sys.argv = sys.argv[:1]
sys.path.insert(0, HERE)
import compare

PATH = os.path.join(HERE, 'adjust.json')
# (What moves with what: a region set after another in the page's flow
# moves as far as the other's last block is moved; the page's flow
# first: the title, the folio, the banner, the table's cells under it.)
PRED = {
    (1, 'folio'): (1, 'masthead'), (2, 'hunyadi'): (2, 'c12'), (1, 'art'): (1, 'art-head'),
    (2, 'section'): (2, 'section-head'), (2, 'hudson'): (2, 'travelers'),
    (1, 'banner'): (1, 'folio'), (1, 'crowd'): (1, 'banner'), (1, 'art-head'): (1, 'banner'),
    (1, 'lead'): (1, 'banner'), (1, 'caption-l'): (1, 'art'), (1, 'caption-r'): (1, 'art'),
    (1, 'names-head'): (1, 'caption-l'), (1, 'loss'): (1, 'caption-l'), (1, 'names-a'): (1, 'names-head'),
    (1, 'names-b'): (1, 'names-head'), (1, 'deep'): (1, 'loss'), (1, 'pearls'): (1, 'loss'),
    (2, 'section-head'): (2, 'folio'), (2, 'c12'): (2, 'section'), (2, 'c34'): (2, 'section'),
    (2, 'c56'): (2, 'section'), (2, 'sos'): (2, 'section'), (2, 'hardman'): (2, 'c12'),
    (2, 'names-cont'): (2, 'c56'), (2, 'travelers'): (2, 'c56'),
}
DAMP = 0.9


def main():
    for n in range(ROUNDS):
        subprocess.run([os.path.join(HERE, 'build.sh')], check=True, stdout=subprocess.DEVNULL)
        adjust = json.load(open(PATH)) if os.path.exists(PATH) else {}
        report = compare.run(ONLY, quiet=True)
        worst = [0.0]
        moved = {}
        cuts = compare.cut_offsets()
        bad = compare.mismatched()
        page_of = {rid: page for page, rs in compare.regions().items() for rid, kind, box in rs}

        def fit(region):
            if region in moved:
                return moved[region]
            pred = PRED.get(region)
            running = fit(pred) if pred else 0.0
            page, rid = region
            if rid in cuts and page_of.get(rid) == page and not bad:
                # (A cut: its margin, less what the blocks before it move.)
                off = max(-40, min(40, (-cuts[rid] - running) * DAMP))
                worst[0] = max(worst[0], abs(off))
                if abs(off) > 0.05:
                    adjust[f'cut/{rid}'] = round(adjust.get(f'cut/{rid}', 0) + off, 2)
                    running += off
            elif region in report and region not in bad:
                seen = set()
                for r in report[region]:
                    if r['key'] in seen:
                        continue
                    seen.add(r['key'])
                    off = max(-40, min(40, (-r['base'] - running) * DAMP))
                    worst[0] = max(worst[0], abs(off))
                    if abs(off) > 0.05:
                        adjust[r['key']] = round(adjust.get(r['key'], 0) + off, 2)
                        running += off
            moved[region] = running
            return running

        for region in list(report) + [(page_of[r], r) for r in cuts]:
            fit(region)
        worst = worst[0]
        json.dump(dict(sorted(adjust.items())), open(PATH, 'w'), indent=0)
        print(f'round {n + 1}: the most {worst:.2f} pt; regions not the spec\'s: {sorted(compare.mismatched())[:8]}')
    subprocess.run([os.path.join(HERE, 'build.sh')], check=True, stdout=subprocess.DEVNULL)


main()
