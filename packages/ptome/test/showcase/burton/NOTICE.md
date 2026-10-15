---
title: "The Anatomy of Melancholy"
source: burton.adoc
looks: [burton]
compare:
  - page: 56
    scan: https://archive.org/download/McGillLibrary-RBSC_FOLIO-673-17111/page/n60.jpg
    note: "Democritus to the Reader: the citations lettered in the margin (1638)"
  - page: 85
    scan: https://archive.org/download/McGillLibrary-RBSC_FOLIO-673-17111/page/n96.jpg
    note: "The synopsis of the First Partition, its first page (1638)"
  - page: 86
    scan: https://archive.org/download/McGillLibrary-RBSC_FOLIO-673-17111/page/n97.jpg
    note: "The synopsis, the causes of melancholy (1638)"
  - page: 90
    scan: https://archive.org/download/McGillLibrary-RBSC_FOLIO-673-17111/page/n100.jpg
    note: "The First Partition's first subsection (1638)"
---

# The Anatomy of Melancholy

Robert Burton's book whole, in a look after its fifth edition (Oxford,
1638). What the work shows: the synopses that open each Partition, trees
of curly braces (`[.braces]` lists, FEAT-6h74yn); Burton's citations, six
thousand eight hundred of them, in the outer margin, each level with its
reference and lettered a, b, c down the page as the folio letters them
(`footnotes_column`, `footnotes_number_style`, FEAT-5qz4y9); the deep
hierarchy of Partitions, Sections, Members and Subsections, the running
heads naming the page's place in it; the Latin in italic, the Greek, the
signs of the planets and the zodiac (FEAT-8zgp4m).

## Sources

| What | Where | SHA-256 |
| --- | --- | --- |
| The Anatomy of Melancholy, Project Gutenberg eBook #10800 (HTML, its images) | https://www.gutenberg.org/cache/epub/10800/pg10800-h.zip | `90e20cea952c7274a756e6ef7d736b595f0de04c407c56c3fba05c86fa02fc98` (its `pg10800-images.html`: `bf8fc33f703973824fba4523dce67545731724fff708b7d9c802b7c18cbd4320`) |
| The frontispiece and Burton's horoscope (PNG), the same edition | in `fetch.yml` with their SHA-256 | in `fetch.yml` |

The text is Project Gutenberg's, which follows a nineteenth-century
edition ("A new edition, corrected, and enriched by translations of the
numerous classical extracts, by Democritus Minor") re-edited against
the 1638 folio by its transcriber. Imported by
`tool/showcase_gutenberg.dart burton`, which writes everything in
`text/`:

- Project Gutenberg's header, licence and introduction are left out, and
  the index, which has no page numbers.
- The notes, numbered through the book in the edition, are footnotes
  where they are referred to.
- The Sections, which have no headings of their own (a Section's first
  Member names it, "Sect. II. Memb. I."), are untitled sections titled
  for the running heads, the outline and the contents as the folio's
  running heads name them, "Part. 1. Sect. 2."; each Member and
  Subsection carries a mark for the running head at the right, "Memb. 1.
  Subs. 4.".
- The first heading of each Partition, "The First Section, Member,
  Subsection.", is the first Member's, "Sect. I. Memb. I.", and its
  first Subsection's, "Subsect. I.".
- The synopses' links to the text are kept.
- The frontispiece's description, run into the text by Project
  Gutenberg's markup, is the image's alternative text.

## Licence

The book is in the public domain (published 1621–1651; the edition
Project Gutenberg follows in the nineteenth century). Project
Gutenberg's edition is a public-domain text in the United States; its
header, licence, trademark and introduction are not reproduced, and its
name is used only in this credit.

## Fonts

IM Fell DW Pica, Noto Serif (the Greek), Noto Sans Symbols (the planets
and the zodiac), Noto Sans Math, and UnifrakturMaguntia (the passages
the edition sets in blackletter), all SIL Open Font License 1.1, from
Google Fonts: `ptome doctor --look burton --looksdir
test/showcase/burton` installs them. Not committed.

## The printing the look follows

The fifth edition, Oxford, 1638, printed for Henry Cripps, a folio:
McGill University Library's copy (RBSC FOLIO 673), scanned by the
Internet Archive,
https://archive.org/details/McGillLibrary-RBSC_FOLIO-673-17111.

Where the look departs from it:

- The folio's catchwords and signatures at the foot of the page, its
  head-pieces and initials, and the brace in its partition headings are
  left out.
- Its centre running heads (a short title of the subject, "Diseases of
  the Minde.") have no source in the text: the heads give the place in
  the hierarchy only.
- The marginal topics ("Mans excellency.") stay in the text, in italic
  before the paragraph they head, as the edition Project Gutenberg
  follows sets them.
- In HTML and EPUB, the notes are footnotes at the end, and the synopses
  are lists whose branches are drawn with a curved rule (the look's CSS),
  not braces.
