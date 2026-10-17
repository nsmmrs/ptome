"""A first punch.spec from align.py's draft (draft.json): each printed
line of each page's columns, decided against the scan afterwards
(fixes.txt, fixes.py). A page `@page N` (its leaf), its columns
`@column`; a line by its kind: `H ` a head, `P ` a paragraph's first
line, `h ` a head within a piece, `  ` a line going on, `V ` a verse's line, `C ` a cut's caption,
`T ` a table's row; `@rule` a rule between pieces, `@cut FILE` a cut
(the transcription's), `# ? OCR` a line the alignment didn't place, the
OCR's reading kept for the reading against the scan.

    python3 -I spec.py > punch.spec.draft
"""
import json, os

WORK = os.environ.get('PUNCH_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/punch'))


def main():
    draft = json.load(open(os.path.join(WORK, 'draft.json')))
    cuts = json.load(open(os.path.join(WORK, 'cuts.json')))
    out = []
    for page in draft:
        out.append(f"@page {page['page']} leaf {page['leaf']}")
        col = 0
        pending = []
        for line in page['lines']:
            if line['col'] != col:
                for c in pending:
                    out.append(f"@cut {c['id']}")
                col = line['col']
                out.append('@column')
                # (The scan's cuts in this column, or across the page from
                # its first: each before the first line at or under its top.)
                pending = sorted((c for c in cuts.get(str(page['page']), [])
                                  if c['col'] == col or (c['col'] == 'across' and col == 1)),
                                 key=lambda c: c['box'][1])
            while pending and line['kind'] != 'I' and line['box'][3] > pending[0]['box'][1] + 10:
                out.append(f"@cut {pending.pop(0)['id']}")
            words = line['words']
            if line['kind'] == '?':
                out.append(f"# ? {line['ocr']}")
                continue
            if line['kind'] == 'R':
                out.append('@rule')
                continue
            if line['kind'] == 'I':
                continue  # (the transcription's cut: the scan's, above)
            text = ''.join(('' if (i == 0 or w.get('join')) else ' ') + w['t'] for i, w in enumerate(words))
            first = words[0]
            if first['s'] and first['k'] in ('H', 'h', 'P', 'V', 'C', 'T'):
                out.append(f"{first['k']} {text}")
            else:
                out.append(f'  {text}')
        for c in pending:
            out.append(f"@cut {c['id']}")
    print('\n'.join(out))


main()
