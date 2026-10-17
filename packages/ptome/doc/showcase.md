# The showcase corpus

Public-domain works (and one CC BY textbook chapter) that show the range
of what Ptome makes from AsciiDoc: each one chosen for something its
printing does that most books don't, set in a look after that printing
or designed to show the feature. They live in `test/showcase/<slug>/`;
EPIC-phf3n2 has the plan.

| Work | What it shows |
| --- | --- |
| [Alice](../test/showcase/alice/NOTICE.md) | Wonderland as Macmillan printed it in 1867, page for page and line for line (`:source-lines:`, its text transcribed from the scan): every page's first and last words, its line breaks and hyphens the printing's, each cut as wide, as tall and where the printing sets it, the Mouse's Tale in type that shrinks down its tail placed line by line from the scan, the running titles divided across the spread, the printer's signatures; Looking-Glass in the same look, with Jabberwocky in mirror type and the chess problem's moves in two columns |
| [Babbage's logarithms](../test/showcase/babbage/NOTICE.md) | Twenty pages of a large numeric table as its 1831 printing sets them, page for page and row for row, the logarithms computed: rows in fives, figures in columns ruled apart, the first three figures where they change, figures put up by rounding dotted under, the arcs at the left, the differences and their proportional parts two abreast or one under another where the printing has them, the head with the logarithm's and the number's first figures |
| [Byrne's Euclid](../test/showcase/byrne/NOTICE.md) | Colour in place of letters, Book I set as its 1847 printing sets it, page for page and line for line: each diagram, woodcut initial and coloured symbol traced from the scan, the symbols set on their lines at the printing's heights (an inline image's `vertical-align`) |
| [Burton's Anatomy of Melancholy](../test/showcase/burton/NOTICE.md) | Brace diagrams: the synopses as trees of braces; Burton's 6,816 citations in the outer margin, lettered on each page; Partitions, Sections, Members and Subsections in the running heads |
| [Mrs Beeton](../test/showcase/beeton/NOTICE.md) | Recipes as structured blocks (ingredients, mode, time, cost, sufficient for, seasonable), 2,700 numbered paragraphs, and a 3,400-line analytical index made from index terms in the text: two columns in the PDF, links in HTML and EPUB |
| [The Book of Common Prayer](../test/showcase/bcp/NOTICE.md) | Red and black: rubrics, red-letter days and verse numbers in red; versicles and responses run in, the Litany's responses from its units scheme, the Psalter quoted whole, the calendar's January ruled |
| [Gibbon](../test/showcase/gibbon/NOTICE.md) | Heavy footnotes (1,931) in two balanced columns at the foot, kept by their references, split across pages; dates in the outer margin |
| [Herbert's The Temple](../test/showcase/herbert/NOTICE.md) | The whole book as its second edition (1633) prints it, page for page and line for line: each line set in as the printing sets it, each block fitted to the scan; shaped verse (The Altar's parts justified, Easter-wings turned under its titles, set in along a curve into wings); drop and woodcut capitals, rules and bands of ornament, turned words, catchwords and signed leaves; an index of titles in two ruled columns; the long s and the ligatures of the Fell types by the font's own rules |
| [Johnson's Dictionary](../test/showcase/johnson/NOTICE.md) | Three pages of the first edition (1755) page for page and line for line (`:source-lines:`, its text transcribed from the scan): two columns of hung entries, their senses and quotations, the authors flush right at the end of the line or on a line of their own, each half line of verse set in where the printing sets it; each column headed by the first three letters of its last word; the folio, the signature and the catchword at the foot |
| [McGuffey's Second Reader](../test/showcase/mcguffey/NOTICE.md) | A schoolbook set as its 1920 printing sets it, page for page and line for line: numbered lessons, each its new words in columns with their marks of pronunciation (macrons, breves, dots and bars above and below, combining marks among them), around its woodcut where the printing sets them there, its paragraphs numbered in their first lines; the key to the marks; the contents with their dot leaders; the script lessons in a copybook hand |
| [Moby-Dick](../test/showcase/moby-dick/NOTICE.md) | Scale (the whole novel, 617 pages) and a novel's apparatus: a dedication page, the Extracts' sources, epigraphs, footnotes, the play-script chapters |
| [Tristram Shandy](../test/showcase/tristram/NOTICE.md) | Typographic play: the black page and the marbled page, chapters that are only their heads, rows of asterisks, plot-line diagrams, dashes of many lengths |
| [OpenStax College Physics 2e](../test/showcase/openstax/NOTICE.md) | A modern textbook chapter (CC BY): learning objectives, notes, worked examples in their steps, equations from MathML (AsciiMath; MathML in the EPUB), numbered figures with descriptions, problems with an answer key at the back, a glossary |
| [Poor Richard's Almanack](../test/showcase/poor-richard/NOTICE.md) | The 1733 almanac as its facsimile sets it, page for page and line for line (`:source-lines:`, its text transcribed from the scan): each page in its frame of rules, each month's verse with its lines set in where the printing sets them and its calendar in the printing's columns, a day a row at the month's own pitch, the signs of the zodiac, the planets and the aspects among the figures; the title page in its sizes, the address with its drop initial and catchword, the anatomy's woodcut with its labels, the folios numbered as the printing numbers them |
| [Punch](../test/showcase/punch/NOTICE.md) | Magazine pages: three 1841 issues in two ruled columns under the running title, cuts with captions in the columns and across the page, pictorial initials, verse, tables of cuts |
| [The New-York Tribune](../test/showcase/tribune/NOTICE.md) | A newspaper's front page, 16 April 1912: seven columns ruled apart, the banner across them, heads over one, two or four columns, the map and pictures, a tally, the survivors' list in its own columns, and stories that jump to the second page |
| [The Tempest](../test/showcase/tempest/NOTICE.md) | One work in two looks: a modern reading edition's (speeches as description lists, shared verse lines stepped, each scene's lines numbered) and the First Folio's, its nineteen pages as the 1623 printing sets them, page for page and line for line (`:source-lines:`, the Text Creation Partnership's transcription read against the scan): two ruled columns in a frame under the running head, speakers run in, long directions hung, words too long for their line turned up or down after a bracket, acts and scenes between rules, the first page's headpiece, title and initial across the page, the last page's epilogue beside the names of the actors, FINIS and the catchword |

## A work's folder

- `<slug>.adoc`: the whole work, its parts in files it includes. Its
  header names its look (`:look: <slug>`, `:looksdir: {docdir}`).
- `<slug>-look.yml` (or several looks): its design for every output
  (`doc/looks.md`), with the fonts it names.
- `images/`: the images small enough to commit (diagrams redrawn as SVG);
  `fetch.yml` lists the rest (scans, Standard Ebooks' traced
  illustrations) by URL and SHA-256, fetched when the work is built; an
  image's `blank` regions (`[x, y, width, height]`) are painted white and
  its `crop` kept, written as a PNG (a woodcut freed of the words printed
  beside it).
- `NOTICE.md`: the work's sources (URLs and SHA-256), the edition, its
  licence and why it is in the public domain, its fonts and their
  licences, the printing its look follows, where it departs from it, and
  in its front matter the pages to set beside scans of that printing.
- `excerpt.adoc` and `expected/`: a page or two that shows what the work
  is there for, and what it converts to (below).

## Building the works

    dart run tool/showcase.dart [SLUG...]

builds each work whole to HTML, EPUB and PDF in `build/showcase/<slug>/`,
and `build/showcase/index.html`, which links them and sets the pages each
NOTICE.md chooses beside the scans of the printing. A work fails when a
font its look names isn't installed, when a conversion warns, or when
EPUBCheck or veraPDF (PDF/UA-1) finds a fault. The fonts come from Google
Fonts or another free library, never from the repository:

    dart run bin/ptome.dart doctor --look <slug> --looksdir test/showcase/<slug> --yes

EPUBCheck is fetched into the work folder when missing (`EPUBCHECK`
names another jar); veraPDF is `VERAPDF`, else the work folder's, else
the path's. The tool is run by hand: whole works never run in
`dart test` (ADR-0025).

## The excerpts

`test/showcase/showcase_test.dart` converts each work's `excerpt.adoc` to
HTML, EPUB and PDF and compares them with `expected/`: the HTML as it is,
the EPUB's entries and the PDF by their SHA-256. The look's faces aren't
there in the tests: the PDF sets every family the look names in the
vendored Noto Serif, so the excerpt tests the layout, not the face. A
change on purpose is a change to the expected files:

    SHOWCASE_UPDATE=1 dart test test/showcase/showcase_test.dart

## Adding a work

1. Its text: a Standard Ebooks production imported by
   `tool/showcase_import.dart` (`--part` for one of several books in a
   work), Project Gutenberg's text without its header and footer
   (`tool/showcase_gutenberg.dart`, a reading of its own for each work), a
   transcription from a facsimile, or generated. US public domain
   (published in 1930 or earlier), preferably also life plus 70 years;
   never CC BY-SA or NC. A CC BY source at a commit (or release) still
   under CC BY, as OpenStax's (`tool/showcase_openstax.dart`).
2. Its look, its fonts in doctor's `lookFonts` where they aren't yet.
3. Its NOTICE.md and the pages to compare.
4. Its excerpt, and `SHOWCASE_UPDATE=1` for the expected files.
5. `tool/showcase.dart <slug>` clean; what it shows a gap in becomes a
   card of its own.
