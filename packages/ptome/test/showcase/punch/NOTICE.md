---
title: "Punch, or the London Charivari"
source: punch.adoc
looks: [punch]
compare:
  - page: 2
    scan: https://upload.wikimedia.org/wikipedia/commons/6/64/Page_001_%28Punch%2C_17_July_1841%29.png
    note: "The first page of the first issue, 17 July 1841"
  - page: 3
    scan: https://upload.wikimedia.org/wikipedia/commons/f/fd/Page_002_%28Punch%2C_17_July_1841%29.png
    note: "Its second page (17 July 1841)"
---

# Punch, or the London Charivari

Three issues of the first volume of Punch (17 July, 14 and 21 August
1841), in a look after the volume's pages. What the work shows: magazine
pages — each issue's pieces in two columns ruled apart under the
running title, short rules between the pieces, headed and unheaded; the
cuts in the columns with their captions under them, the large cuts
across the page (`image_role_cut_scope: page`); the pictorial initials,
a piece's first letter drawn as a picture floated beside its text, the
letter itself hidden (`role_hide_display: none`); verse, prescriptions
and a thermometer as tables, the Royal Alphabet with a cut to each
letter (FEAT-n5k533). The catalogue of the Fine Arts found BUG-l91thh: a
cell spanning rows that a column break splits left an empty row in the
tagged PDF.

## Sources

| What | Where | SHA-256 |
| --- | --- | --- |
| Punch, 17 July 1841, Project Gutenberg eBook #13639 (HTML, its cuts) | https://www.gutenberg.org/cache/epub/13639/pg13639-h.zip | `690d8fb4e3b5d2938dec54a4427ab6247c013d51560138bbd047f11c101ad2f0` |
| Punch, 14 August 1841, eBook #14923 | https://www.gutenberg.org/cache/epub/14923/pg14923-h.zip | `7717739153ff6013e5aa9f9a73d5b6b5a087a8b627c2d46c9403aa30b19cfbd6` |
| Punch, 21 August 1841, eBook #14924 | https://www.gutenberg.org/cache/epub/14924/pg14924-h.zip | `d5769010b447fc54016e47c26e2ec18a333a4286ca279be932a82b03ab7e46cd` |
| The cuts (PNG), the same editions | in `fetch.yml` with their SHA-256 | in `fetch.yml` |

The issues are three of the first volume's first six: the others (24
and 31 July, 7 August) hold racial and religious caricatures, in their
text and their cuts, that the showcase leaves out.

Imported by `tool/showcase_gutenberg.dart punch`, which writes each
issue to `text/`:

- Project Gutenberg's header, licence and page numbers are left out,
  and the masthead it repeats over each issue (the look sets the title
  over every page, as the volume does).
- Each issue is a chapter titled by its date; its pieces are sections,
  their subheads discrete headings; Project Gutenberg's rules between
  pieces are thematic breaks.
- The cuts are as wide as Project Gutenberg sets them: a quarter of its
  page more than half the column, half its page the column, its whole
  page the page across (the `cut` role); their captions are their titles.
- The side notes are footnotes; the tables keep their spans (a span
  that runs past the table's end is cut to it), without header rows.

## Licence

Punch's first volume is in the public domain (published 1841). Project
Gutenberg's editions are public-domain texts in the United States; their
headers, licences and trademarks are not reproduced, and their name is
used only in this credit. The pages on Wikimedia Commons that the build
compares with are in the public domain.

## Fonts

Old Standard TT and Noto Serif (both SIL Open Font License 1.1), from
Google Fonts: `ptome doctor --look punch --looksdir test/showcase/punch`
installs them. Not committed.

## The printing the look follows

The first volume, London, 1841: the pages of the first issue on
Wikimedia Commons ("Page 001 (Punch, 17 July 1841).png" and on).

Where the look departs from it:

- The running title is set in Old Standard TT's capitals, not the
  volume's outlined display letters.
- The cuts are where the transcription puts them, not where the volume
  sets them on the page.
