# The showcase corpus

Public-domain works (and one CC BY textbook chapter) that show the range
of what Ptome makes from AsciiDoc: each one chosen for something its
printing does that most books don't, set in a look after that printing
or designed to show the feature. They live in `test/showcase/<slug>/`;
EPIC-phf3n2 has the plan.

| Work | What it shows |
| --- | --- |
| [Alice](../test/showcase/alice/NOTICE.md) | Wonderland as Macmillan printed it in 1867, page for page and line for line (`:source-lines:`, its text transcribed from the scan): every page's first and last words, its line breaks and hyphens the printing's, each cut as wide, as tall and where the printing sets it, the Mouse's Tale in type that shrinks down its tail placed line by line from the scan, the running titles divided across the spread, the printer's signatures; Looking-Glass in the same look, with Jabberwocky in mirror type and the chess problem's moves in two columns |
| [Babbage's logarithms](../test/showcase/babbage/NOTICE.md) | A large numeric table, generated: rows in fives, figures in columns, heads on every page, the page's range in its head, a tinted page |
| [Byrne's Euclid](../test/showcase/byrne/NOTICE.md) | Colour in place of letters: each proposition's diagram redrawn as SVG in red, yellow, blue and black, the lines, circles, triangles and angles named in the text by coloured figures set inline; diagrams floated beside enunciations with large initials |
| [Burton's Anatomy of Melancholy](../test/showcase/burton/NOTICE.md) | Brace diagrams: the synopses as trees of braces; Burton's 6,816 citations in the outer margin, lettered on each page; Partitions, Sections, Members and Subsections in the running heads |
| [Mrs Beeton](../test/showcase/beeton/NOTICE.md) | Recipes as structured blocks (ingredients, mode, time, cost, sufficient for, seasonable), 2,700 numbered paragraphs, and a 3,400-line analytical index made from index terms in the text: two columns in the PDF, links in HTML and EPUB |
| [The Book of Common Prayer](../test/showcase/bcp/NOTICE.md) | Red and black: rubrics, red-letter days and verse numbers in red; versicles and responses run in, the Litany's responses from its units scheme, the Psalter quoted whole, the calendar's January ruled |
| [Gibbon](../test/showcase/gibbon/NOTICE.md) | Heavy footnotes (1,931) in two balanced columns at the foot, kept by their references, split across pages; dates in the outer margin |
| [Herbert's The Temple](../test/showcase/herbert/NOTICE.md) | Shaped verse: The Altar's lines set in to make an altar, Easter-wings turned sideways on two pages, its lines a pair of wings; the long s and the ligatures of the Fell types by the font's own rules; stanzas' indents |
| [Johnson's Dictionary](../test/showcase/johnson/NOTICE.md) | A dictionary's page: two columns of hung entries, their senses and quotations, the authors flush right at the end of the line; each column headed by the first three letters of its last word; a catchword at the foot of each page |
| [McGuffey's Second Reader](../test/showcase/mcguffey/NOTICE.md) | A schoolbook: numbered lessons, each its new words in columns with their marks of pronunciation (macrons, breves, dots and bars above and below, combining marks among them), its woodcut and numbered paragraphs; the key to the marks; the script lessons in a copybook hand |
| [Moby-Dick](../test/showcase/moby-dick/NOTICE.md) | Scale (the whole novel, 617 pages) and a novel's apparatus: a dedication page, the Extracts' sources, epigraphs, footnotes, the play-script chapters |
| [Tristram Shandy](../test/showcase/tristram/NOTICE.md) | Typographic play: the black page and the marbled page, chapters that are only their heads, rows of asterisks, plot-line diagrams, dashes of many lengths |
| [OpenStax College Physics 2e](../test/showcase/openstax/NOTICE.md) | A modern textbook chapter (CC BY): learning objectives, notes, worked examples in their steps, equations from MathML (AsciiMath; MathML in the EPUB), numbered figures with descriptions, problems with an answer key at the back, a glossary |
| [Poor Richard's Almanack](../test/showcase/poor-richard/NOTICE.md) | Dense tables in small type: the 1733 almanac's twelve months, each a page of its calendar in seven ruled columns, the signs of the zodiac, the planets and the aspects among the figures, the proverbs down the last column; its title page, its anatomy woodcut |
| [Punch](../test/showcase/punch/NOTICE.md) | Magazine pages: three 1841 issues in two ruled columns under the running title, cuts with captions in the columns and across the page, pictorial initials, verse, tables of cuts |
| [The New-York Tribune](../test/showcase/tribune/NOTICE.md) | A newspaper's front page, 16 April 1912: seven columns ruled apart, the banner across them, heads over one, two or four columns, the map and pictures, a tally, the survivors' list in its own columns, and stories that jump to the second page |
| [The Tempest](../test/showcase/tempest/NOTICE.md) | One source in two looks, a modern reading edition's and the First Folio's: speeches as description lists, shared verse lines stepped, each scene's lines numbered; two ruled columns in a frame |

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
