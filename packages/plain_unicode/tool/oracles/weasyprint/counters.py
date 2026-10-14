"""WeasyPrint's counter styles, as an oracle for plain_unicode's.

Reads JSON from stdin: {"css": rules to add, "styles": [names],
"values": [integers]}; writes JSON to stdout: for each style, for each
value, [what counter(c, style) writes, the list item marker]. Read from
the laid-out boxes (logical order), not from a PDF.

    weasyprint's python -I tool/oracles/weasyprint/counters.py < in.json

Run it with the interpreter WeasyPrint is installed in (the shebang of
`weasyprint`); test/counter_styles_test.dart finds it.
"""
import json
import sys

from weasyprint import HTML


def texts(box, pseudo, out):
    """Appends the text of each `pseudo` box under `box`, in order."""
    if (getattr(box, 'element_tag', None) or '').endswith('::' + pseudo):
        out.append(''.join(_text(box)))
        return
    for child in getattr(box, 'children', []):
        texts(child, pseudo, out)


def _text(box):
    if hasattr(box, 'text'):
        yield box.text
    for child in getattr(box, 'children', []):
        yield from _text(child)


def main():
    job = json.load(sys.stdin)
    styles, values = job['styles'], job['values']
    rules = [job.get('css', '')]
    body = []
    for i, style in enumerate(styles):
        rules.append('.s%d::before{content:counter(c,%s)}' % (i, style))
        rules.append('.l%d{list-style-type:%s}' % (i, style))
        for v in values:
            body.append('<p class="s%d" style="counter-reset:c %d"></p>'
                        % (i, v))
            # (The item adds one to what counter-set sets.)
            body.append('<ol class="l%d"><li style="counter-set:list-item'
                        ' %d">x</li></ol>' % (i, v - 1))
    html = ('<html><head><meta charset="utf-8"><style>@page{size:A3}'
            'p,ol{margin:0}%s</style></head><body>%s</body></html>'
            % (''.join(rules), ''.join(body)))
    befores, markers = [], []
    for page in HTML(string=html).render().pages:
        texts(page._page_box, 'before', befores)
        texts(page._page_box, 'marker', markers)
    out, k = [], 0
    for _ in styles:
        row = []
        for _ in values:
            row.append([befores[k], markers[k]])
            k += 1
        out.append(row)
    json.dump(out, sys.stdout, ensure_ascii=False)


main()
