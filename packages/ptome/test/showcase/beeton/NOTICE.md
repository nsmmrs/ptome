---
title: "The Book of Household Management"
source: beeton.adoc
looks: [beeton]
compare:
  - page: 485
    scan: https://archive.org/download/b20392758/page/n509.jpg
    note: "Recipes for ducks: Hashed Duck, To Ragout a Duck Whole (1861)"
  - page: 486
    scan: https://archive.org/download/b20392758/page/n510.jpg
    note: "Roast Ducks, the Buenos Ayres duck in small type (1861)"
  - page: 1213
    scan: https://archive.org/download/b20392758/page/n20.jpg
    note: "The analytical index (1861: by paragraph; here, made from the text, by page)"
---

# The Book of Household Management

Isabella Beeton's book whole, in a look after its first edition (1861).
What the work shows: recipes as structured blocks, each recipe a section
with the `recipe` role whose paragraphs are typed by their roles
(`ingredients`, `mode`, `particulars`: the time, the average cost, how
many it is sufficient for, when it is seasonable), the natural history
between them in small type (`note`); 2,700 numbered paragraphs; and the
analytical index, 3,400 lines that refer to the paragraphs, turned into
index terms in the paragraphs they name, so that every format makes the
index from the text: the PDF in two columns with page numbers, sorted
letter by letter, the HTML and EPUB linking to the sections
(FEAT-m0m85t). A few engravings are set where the text has them.

## Sources

| What | Where | SHA-256 |
| --- | --- | --- |
| The Book of Household Management, Project Gutenberg eBook #10136 (HTML) | https://www.gutenberg.org/cache/epub/10136/pg10136-h.zip | `52acd965833b46e7c1186b975cdc0274101294c101d09caed8a002723dce6110` (its `pg10136-images.html`: `c4e73b204f3f3d814d26606ca283c3b3f3e41a8d26aef55e65158268bec3b395`) |
| The engraved title page in colour (Wellcome Library's copy), the Rouen ducks and the Bow-bill ducks, scans of the first edition on Wikimedia Commons | in `fetch.yml` with their SHA-256 | in `fetch.yml` |

Imported by `tool/showcase_gutenberg.dart beeton`, which writes
everything in `text/`:

- Project Gutenberg's header and licence are left out, and the
  general contents and the lists of engravings and coloured plates: the
  contents are made by the PDF (`:toc:`), titled as the book's.
- The chapters are titled as the general contents titles them ("Recipes."
  for the chapters of recipes); the "RECIPES." heading before each such
  chapter is left out.
- A heading is a heading element, a paragraph the transcription sets
  apart with a margin, or a short one in capitals; a recipe is a heading
  whose next paragraphs hold one numbered "INGREDIENTS".
- The numbered paragraphs are anchored (`p-933`), numbered in order: the
  numbers of the text's own lists are not, and four misprints (1510 as
  510, 1526 as 1536, 2071 as 1071, 2548 as 4548) are read as the numbers
  they follow.
- Each line of the analytical index is an index term (with its heading,
  and a heading's heading, for a line set in under them) in each
  paragraph it gives; a range (`2705-7`) is every paragraph in it; a page
  reference (`p. 955`) has no paragraph and is left out, and so are the
  11 paragraph numbers the text lacks.
- The fractions the transcription writes "1-1/2" are the edition's "1½".
- The engravings the work hasn't are left out of the text, with the
  transcription's "[Illustration]" marks.

## Licence

The book is in the public domain (published 1859–61; Isabella Beeton died
in 1865). Project Gutenberg's edition is a public-domain text in the
United States; its header, licence and trademark are not reproduced, and
its name is used only in this credit. The scans on Wikimedia Commons are
in the public domain.

## Fonts

Old Standard TT and Noto Serif (both SIL Open Font License 1.1), from
Google Fonts: `ptome doctor --look beeton --looksdir test/showcase/beeton`
installs them. Not committed.

## The printing the look follows

The first edition, London, S. O. Beeton, 1861: the Wellcome Library's
copy, scanned by the Internet Archive,
https://archive.org/details/b20392758.

Where the look departs from it:

- The analytical index is at the end, by page, made from the text: the
  first edition sets it at the front, by paragraph.
- The headings are in Old Standard TT's bold, not the edition's
  Clarendon; the running heads are the chapters' titles on both sides
  ("Recipes." for a chapter of recipes, where the edition has "MODERN
  HOUSEHOLD COOKERY." over the subject, "POULTRY.").
- The engravings, five hundred of them, and the coloured plates are left
  out but three.
