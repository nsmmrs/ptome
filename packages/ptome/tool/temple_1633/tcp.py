"""The TCP transcription as pages of lines: [(page n, facs, [line text])]."""
import re, sys
import xml.etree.ElementTree as ET

NS = '{http://www.tei-c.org/ns/1.0}'


def text_of(el, out):
    """Flatten an element into text, gaps as '•'."""
    tag = el.tag.replace(NS, '')
    if tag == 'gap':
        d = el.find(NS + 'desc')
        out.append(d.text if d is not None and d.text else '•')
        out.append(el.tail or '')
        return
    if tag == 'g':
        ref = el.get('ref', '')
        out.append('-' if 'EOLhyphen' in ref else (el.text or ''))
        out.append(el.tail or '')
        return
    if tag == 'note':
        out.append(el.tail or '')
        return
    out.append(el.text or '')
    for c in el:
        text_of(c, out)
    out.append(el.tail or '')


def pages(path):
    root = ET.parse(path).getroot()
    body = root.find(f'{NS}text')
    result = []
    cur = None

    def walk(el):
        nonlocal cur
        tag = el.tag.replace(NS, '')
        if tag == 'pb':
            cur = [el.get('n'), el.get('facs'), []]
            result.append(cur)
            return
        if tag in ('l', 'head', 'p', 'item', 'label', 'trailer', 'signed', 'byline', 'closer', 'salute', 'dateline', 'argument', 'opener'):
            has_pb = el.find(f'.//{NS}pb') is not None
            if not has_pb:
                out = []
                text_of(el, out)
                t = re.sub(r'\s+', ' ', ''.join(out)).strip()
                if cur is not None and t:
                    cur[2].append((tag, t))
                return
        for c in el:
            walk(c)

    walk(body)
    return result


if __name__ == '__main__':
    for n, facs, lines in pages(sys.argv[1]):
        print(f'=== {n} {facs}')
        for tag, t in lines:
            print(f'  {tag:5s} {t}')
