"""The TCP transcription of The Temple (A03058) as a sequence of records,
its structure kept: each line, heading, paragraph or index entry with
its words (each word's text and whether it is italic), its poem, its
stanza and the page it starts on; a page break inside an element splits
it (the part after the break on the next page).

    records(path) -> [dict(kind, words, page, poem, lg, part, decor, ...)]
"""
import re
import xml.etree.ElementTree as ET

NS = '{http://www.tei-c.org/ns/1.0}'
BLOCKS = {'l', 'head', 'p', 'item', 'label', 'trailer', 'signed', 'byline', 'closer',
          'speaker', 'stage', 'q', 'bibl'}


def tag(el):
    return el.tag.replace(NS, '')


class Walker:
    def __init__(self):
        self.records = []
        self.page = None
        self.poem = -1
        self.lg = -1
        self.list = -1
        self.ctx = []  # div types
        self.cur = None  # the record being filled

    def new(self, kind, el):
        self.cur = dict(kind=kind, words=[], page=self.page, poem=self.poem,
                        lg=self.lg if self.in_lg else None, div=list(self.ctx),
                        list=self.list if self.in_list else None, decor=False,
                        rend=el.get('rend'))
        self.records.append(self.cur)
        self.pending = ''

    def text(self, s, italic):
        if not s:
            return
        # (Words: a word divided by the text's own hyphen at a line's end,
        # `<g ref="char:EOLhyphen"/>`, kept whole; spaces end words.)
        parts = re.split(r'(\s+)', s)
        for p in parts:
            if not p:
                continue
            if p.isspace():
                self.flush()
                continue
            self.pending_parts.append((p, italic))

    def flush(self):
        if self.pending_parts:
            # (A word in pieces of differing style: its pieces kept apart
            # as spans of one word.)
            self.cur['words'].append(list(self.pending_parts))
            self.pending_parts = []

    def inline(self, el, italic):
        t = tag(el)
        if t == 'pb':
            self.flush()
            self.page = self.pb(el)
            # (The element goes on, on the next page: a new record of its
            # kind.)
            kind = self.cur['kind']
            self.new(kind, el)
            self.cur['cont'] = True
            self.text(el.tail, italic)
            return
        if t == 'gap':
            d = el.find(NS + 'desc')
            self.text((d.text if d is not None and d.text else '•'), italic)
            self.text(el.tail, italic)
            return
        if t == 'g':
            ref = el.get('ref', '')
            if 'EOLhyphen' in ref:
                pass  # (a word divided at the first edition's line end: whole)
            elif el.text:
                self.text(el.text, italic)
            self.text(el.tail, italic)
            return
        if t == 'note':
            self.text(el.tail, italic)
            return
        if t == 'seg' and el.get('rend') == 'decorInit':
            self.cur['decor'] = True
        it = (not italic) if t == 'hi' else italic
        self.text(el.text, it)
        for c in el:
            self.inline(c, it)
        self.text(el.tail, italic)

    in_lg = False
    in_list = False

    def walk(self, el):
        t = tag(el)
        if t == 'pb':
            self.page = self.pb(el)
            return
        if t in BLOCKS:
            self.new(t, el)
            self.pending_parts = []
            self.text(el.text, False)
            for c in el:
                self.inline(c, False)
            self.flush()
            # (The tail of a block: between blocks, ignored.)
            return
        if t == 'div':
            self.ctx.append(el.get('type'))
            if el.get('type') == 'poem':
                self.poem += 1
            for c in el:
                self.walk(c)
            self.ctx.pop()
            return
        if t == 'lg':
            self.lg += 1
            was = self.in_lg
            self.in_lg = True
            for c in el:
                self.walk(c)
            self.in_lg = was
            return
        if t == 'list':
            self.list += 1
            was = self.in_list
            self.in_list = True
            for c in el:
                self.walk(c)
            self.in_list = was
            return
        for c in el:
            self.walk(c)

    pbs = None

    def pb(self, el):
        """A page break: its place among the page breaks."""
        if self.pbs is None:
            self.pbs = []
        key = (el.get('n'), el.get('facs'))
        # (Each break a page, two to a facsimile's spread: the scan's leaf
        # the break's place less one, the film's cover before the title.)
        self.pbs.append((len(self.pbs), *key))
        return len(self.pbs) - 2


def records(path):
    root = ET.parse(path).getroot()
    w = Walker()
    w.pending_parts = []
    w.walk(root.find(f'{NS}text'))
    out = [r for r in w.records if r['words']]
    # (The scan's leaf of each break: the film's pages filmed twice, a
    # repeated number with no text, skipped.)
    used = {r['page'] for r in out}
    leaf = {}
    skipped = 0
    seen = []
    for seq, n, facs in w.pbs:
        k = seq - 1
        if n is not None and n in seen[-4:] and k not in used:
            skipped += 1
            leaf[k] = None
        else:
            leaf[k] = k - skipped
        seen.append(n)
    for r in out:
        r['leaf'] = leaf[r['page']]
    records.pbs = w.pbs
    for r in out:
        r['plain'] = ' '.join(''.join(p for p, _ in word) for word in r['words'])
    return out


if __name__ == '__main__':
    import sys, collections
    rs = records(sys.argv[1])
    print(len(rs), collections.Counter(r['kind'] for r in rs))
    pages = collections.OrderedDict()
    for r in rs:
        pages.setdefault(r['page'], 0)
        pages[r['page']] += 1
    print(list(pages.items())[:12], len(pages))
    for r in rs[:12]:
        print(r['page'], r['kind'], r['poem'], r['lg'], r['decor'], r.get('cont'), r['plain'][:70])
