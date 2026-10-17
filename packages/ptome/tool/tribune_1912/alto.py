"""The Library of Congress's OCR of the two pages (ALTO, ABBYY FineReader,
its units 1/1200 inch): each line its box and its words' boxes and
text, in the scan's pixels (400 to the inch, a third of ALTO's units),
its block's id. Written to TRIBUNE_WORK/alto.json.

    python3 -I alto.py
"""
import json, os, re, sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK, PAGES

NS = '{http://schema.ccs-gmbh.com/ALTO}'


def box(e):
    x, y, w, h = (float(e.get(k)) / 3 for k in ('HPOS', 'VPOS', 'WIDTH', 'HEIGHT'))
    return [round(x), round(y), round(x + w), round(y + h)]


def main():
    out = {}
    for page, seq in PAGES.items():
        root = ET.parse(os.path.join(WORK, f'seq{seq}.xml')).getroot()
        lines = []
        for block in root.iter(NS + 'TextBlock'):
            for line in block.iter(NS + 'TextLine'):
                words = [{'t': s.get('CONTENT'), 'box': box(s), 'wc': float(s.get('WC') or 0)}
                         for s in line.iter(NS + 'String')]
                if words:
                    lines.append({'block': block.get('ID'), 'box': box(line), 'words': words})
        out[page] = lines
    json.dump(out, open(os.path.join(WORK, 'alto.json'), 'w'))
    for page, lines in out.items():
        print(page, len(lines), 'lines')


main()
