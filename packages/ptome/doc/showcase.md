# The showcase corpus

Public-domain works (and one CC BY textbook chapter) that show the range
of what Ptome makes from AsciiDoc: each one chosen for something its
printing does that most books don't, set in a look after that printing
or designed to show the feature. They live in `test/showcase/<slug>/`;
EPIC-phf3n2 has the plan.

| Work | What it shows |
| --- | --- |
| [Alice](../test/showcase/alice/NOTICE.md) | Illustrations the text runs beside, the Mouse's Tale in type that shrinks down its tail, Jabberwocky in mirror type, the chess problem's moves in two columns |
| [Moby-Dick](../test/showcase/moby-dick/NOTICE.md) | Scale (the whole novel, 617 pages) and a novel's apparatus: a dedication page, the Extracts' sources, epigraphs, footnotes, the play-script chapters |
| [Tristram Shandy](../test/showcase/tristram/NOTICE.md) | Typographic play: the black page and the marbled page, chapters that are only their heads, rows of asterisks, plot-line diagrams, dashes of many lengths |
| [The Tempest](../test/showcase/tempest/NOTICE.md) | One source in two looks, a modern reading edition's and the First Folio's: speeches as description lists, shared verse lines stepped, each scene's lines numbered; two ruled columns in a frame |

## A work's folder

- `<slug>.adoc`: the whole work, its parts in files it includes. Its
  header names its look (`:look: <slug>`, `:looksdir: {docdir}`).
- `<slug>-look.yml` (or several looks): its design for every output
  (`doc/looks.md`), with the fonts it names.
- `images/`: the images small enough to commit (diagrams redrawn as SVG);
  `fetch.yml` lists the rest (scans, Standard Ebooks' traced
  illustrations) by URL and SHA-256, fetched when the work is built.
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
   work), Project Gutenberg's text without its header and footer, a
   transcription from a facsimile, or generated. US public domain
   (published in 1930 or earlier), preferably also life plus 70 years;
   never CC BY-SA or NC.
2. Its look, its fonts in doctor's `lookFonts` where they aren't yet.
3. Its NOTICE.md and the pages to compare.
4. Its excerpt, and `SHOWCASE_UPDATE=1` for the expected files.
5. `tool/showcase.dart <slug>` clean; what it shows a gap in becomes a
   card of its own.
