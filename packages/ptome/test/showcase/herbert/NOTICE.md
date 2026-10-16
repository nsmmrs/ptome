---
title: "The Temple"
source: herbert.adoc
looks: [herbert]
compare:
  - page: 1
    scan: https://archive.org/download/bim_early-english-books-1475-1640_the-temple-sacred-poems_herbert-george_1633/page/n0.jpg
    note: "The title page in its frame of flowers, \"The second Edition\" (1633)"
  - page: 9
    scan: https://archive.org/download/bim_early-english-books-1475-1640_the-temple-sacred-poems_herbert-george_1633/page/n8.jpg
    note: "The Church-porch: its band of ornament, its woodcut capital, its stanzas set in (1633)"
  - page: 26
    scan: https://archive.org/download/bim_early-english-books-1475-1640_the-temple-sacred-poems_herbert-george_1633/page/n25.jpg
    note: "The Altar, each part of its shape justified, between bands of ornament (1633)"
  - page: 42
    scan: https://archive.org/download/bim_early-english-books-1475-1640_the-temple-sacred-poems_herbert-george_1633/page/n41.jpg
    note: "Easter-wings, its first stanza turned under its title (1633)"
  - page: 43
    scan: https://archive.org/download/bim_early-english-books-1475-1640_the-temple-sacred-poems_herbert-george_1633/page/n42.jpg
    note: "Easter-wings, its second stanza on the facing page (1633)"
  - page: 192
    scan: https://archive.org/download/bim_early-english-books-1475-1640_the-temple-sacred-poems_herbert-george_1633/page/n191.jpg
    note: "The Church Militant, its woodcut capital six lines deep (1633)"
  - page: 201
    scan: https://archive.org/download/bim_early-english-books-1475-1640_the-temple-sacred-poems_herbert-george_1633/page/n200.jpg
    note: "The titles of the poems, in two columns (1633)"
---

# The Temple

George Herbert's The Temple whole, as Thomas Buck and Roger Daniel
printed its second edition (Cambridge, 1633), page for page and line for
line: the title page, the Printers to the Reader, the Dedication, The
Church-porch, The Church, The Church Militant, L'Envoy and the titles of
the poems at the end. What the work shows: a duodecimo of verse — its
stanzas' lines set in as far as the printing sets each, its shaped poems
(The Altar's parts each a paragraph its lines fill, justified;
Easter-wings' two stanzas each turned on its page under its title, set in
along a curve into wings: roles `sideways`, `clockwise`, `in-flow`), its
poems' titles with their pilcrows (a section sign where the printing ran
out of them), its rules and bands of ornament between them, its drop
capitals and woodcut capitals, its dialogue with its speakers in the
margin, its words turned up or down after a bracket where a line is too
long (roles `turn-up`, `turn-down`: `role_<role>_turnover`, FEAT-dfwxy9); the long s of the Fell types, with its ligatures (ſt, ſh, ſl, ſſ),
and their ct, set by the font's own rules
(`base_font_variant_alternates: historical-forms`,
`base_font_variant_ligatures: discretionary-ligatures`); and an index of
titles in two ruled columns.

In the PDF each page is the printing's page of its leaf: it starts and
ends with the printing's words, each line breaks where the printing's
does (`:source-lines:`), each line is set in as far as the printing sets
it (the ink's start on the scan, against the page's own edge), and each
block — a title, a stanza, a rule, a band, a page's foot line — sits where
the scan shows it, within a tenth of a point (its own `margin-top`, fitted
to the scan: `tool/temple_1633`). The running heads are the printing's
("The Church-porch.", "The Church.", "The Church Militant.") with their
folios outside, a part's first page its folio alone, centred; each page's
foot line is the printing's, its catchword and on the first five leaves
of each gathering its signature (A, A 2 … A 5).

## Sources

| What | Where | SHA-256 |
| --- | --- | --- |
| The text | the Text Creation Partnership's transcription of the first edition (EEBO-TCP A03058, `A03058.xml`, https://github.com/textcreationpartnership/A03058, CC0), read line by line against the scan below and corrected where the second edition prints otherwise (`tool/temple_1633`: 371 lines decided by eye, `decisions.tsv`, and the gaps the TCP marks filled) | `30ca50a71ca6f5b67b10a02abece1786382bad31d632fb57d0d4a2b6d15f68a3` |
| The scan and its OCR | https://archive.org/details/bim_early-english-books-1475-1640_the-temple-sacred-poems_herbert-george_1633: `…_jp2.zip` (the leaves, 800 ppi on the film), `…_hocr.html` | `2ffbc59c414811579682da304bb9097517bdc4bc42ffd56514acfe1dfeba5791`, `e9577d93b77f60bf75ee52bf6e43d43e8979944382dcb92f3c7a18ce41c8f5df` |
| The ornaments | cut from the same scan's page images (the bands, the woodcut capitals, the title page's frame, its rules and flower, the flowers, the index's rules), in `fetch.yml` with their SHA-256 | in `fetch.yml` |

The transcription keeps the edition's spelling, its capitals and its
punctuation, and its u, v, i and j; it writes the round s for every s,
the long s coming from the font. Where the TCP's first edition and the
second differ (a word, a line's order, a point the TCP couldn't read,
`▪`), the second edition's reading is set; the first's are in
`tool/temple_1633`'s review. A line's first letter the TCP lost to the
film is restored, as is the turned part of a line it joined to its line.

## Licence

The Temple is in the public domain (published 1633; George Herbert died
in 1633). The TCP's transcription is dedicated to the public domain
(CC0). The work's corrections and markup are its own (MIT, as the
repository). The scans are not committed: `tool/showcase.dart` fetches
the page images it cuts the ornaments from and the pages it compares into
its cache.

## Fonts

IM Fell DW Pica, roman and italic (SIL Open Font License 1.1; Igino
Marini's revival of the Fell types, cut in the 1670s), from Google
Fonts: `ptome doctor --look herbert --looksdir test/showcase/herbert`
installs it. Not committed.

## The printing the look follows

The second edition, Cambridge, Thomas Buck and Roger Daniel, 1633 (its
title page: "The second Edition"), a duodecimo, in the British Library's
copy filmed for Early English Books and scanned by the Internet Archive,
https://archive.org/details/bim_early-english-books-1475-1640_the-temple-sacred-poems_herbert-george_1633.
The page is 241 × 422 pt (85 × 149 mm), the scan's scale set from the
leaf's height.

Where the look departs from it:

- IM Fell DW Pica, a type of the 1670s, stands in for the edition's
  roman and italic: its letters are a little wider or narrower here and
  there, so that a line's end falls a point or two from the printing's;
  the long s falls where the font's rules put it, not always where the
  printing has it. The drop capitals are the font's, two lines deep; the
  spaced capitals (ALTAR, HEART) are its small capitals' size.
- The title page's lines are set in type over its frame, rules and flower
  cut from the scan; the woodcut capitals, the bands of ornament, the
  flowers and the index's column rules are the scan's.
- An indent is the printing's to half a point, measured where the film
  is skewed and the page curled; where the scan doesn't show it clearly,
  a stanza's indents are its poem's other stanzas' of the same shape.
- Joseph's coat's VV is a W; the turned words' brackets and the speakers
  stand where the printing's do to a point or two.
- In HTML and EPUB the poems run without their pages, ornaments, rules
  and feet, a woodcut capital's lines whole; the title page and the
  titles of the poems are the PDF's alone; Easter-wings is set upright,
  an e-book's page can't be turned. The long
  s and the ligatures come from the font's features where the reader's
  browser applies them (`font-feature-settings`).
- In the excerpt test, the long s and the ligatures are left out: they
  are in none of the fonts the tests commit.
