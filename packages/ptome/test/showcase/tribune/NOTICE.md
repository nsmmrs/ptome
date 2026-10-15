---
title: "New-York Tribune"
source: tribune.adoc
looks: [tribune]
compare:
  - page: 1
    scan: https://tile.loc.gov/image-services/iiif/service:ndnp:dlc:batch_dlc_keady_ver01:data:sn83030214:00206531526:1912041601:0303/full/pct:25/0/default.jpg
    note: "The front page, 16 April 1912"
  - page: 2
    scan: https://tile.loc.gov/image-services/iiif/service:ndnp:dlc:batch_dlc_keady_ver01:data:sn83030214:00206531526:1912041601:0304/full/pct:25/0/default.jpg
    note: "The second page: the lead story and the list of survivors going on (its first and fifth columns)"
---

# New-York Tribune

The front page of the New-York Tribune of Tuesday, 16 April 1912, the
morning after the Titanic sank, with the two stories it jumps to the
second page, in a look after the page. What the work shows: a
newspaper's layout — a broadsheet of seven columns ruled apart (a table
whose cells hold the stories, `grid=all`); the blackletter title
between its ears and the folio line between rules; the banner across
the page; heads across one, two or four columns, each story under its
headline in condensed gothic capitals or a roman, its decks and
crosslines centred; the map and the pictures across four columns over
their captions; a tally of the lost, its figures at the right; the list
of survivors in two columns of its own; and jump
lines, worded by `jump-template` from where the story goes on
("Continued on page 2.", "Continued from page 1."), which needed
`findBy` to reach into table cells as Asciidoctor's does and an EPUB's
references to reach a later cell (BUG-xmdjm0) (FEAT-tw99x9).

## Sources

| What | Where | SHA-256 |
| --- | --- | --- |
| `text/` | transcribed for the work from the Library of Congress's scans of the first and second pages, Chronicling America, https://www.loc.gov/resource/sn83030214/1912-04-16/ed-1/ (images 1 and 2), with their OCR (ALTO) as a starting point | the scans' full-size JPEGs: `a15635a917e349a78e0357affcf856c018215d37a8d3e34274963b001224e9b3` (page 1), `309e07ba4e92a71c919d6f990439c30a8551ad68a0a1befc45d83d296a8e4792` (page 2) |
| The map and the pictures, the region of the first page's scan | in `fetch.yml` with its SHA-256 | in `fetch.yml` |

The transcription keeps the paper's words, spelling ("to-day",
"aid"), capitals, punctuation and its misprints and the wireless's
garbled names in the list of survivors; it corrects only the OCR. The
second page's other stories, and the front page's below the Olympic's
message, are left out.

## Licence

The New-York Tribune of 1912 is in the public domain in the United
States (published 1912, before 1930); the Library of
Congress's scans of it carry no known restrictions. The transcription
is the work's own (MIT, as the repository). The scans are not
committed: `tool/showcase.dart` fetches the region it uses and the
pages it compares into its cache.

## Fonts

UnifrakturMaguntia (the title), Fira Sans Condensed (the gothic heads)
and Old Standard TT (the text and the roman heads), all SIL Open Font
License 1.1, from Google Fonts: `ptome doctor --look tribune --looksdir
test/showcase/tribune` installs them. Not committed.

## The printing the look follows

The New-York Tribune, Tuesday, 16 April 1912, its first and second
pages, scanned for Chronicling America by the Library of Congress
(reel 00206531526), https://www.loc.gov/resource/sn83030214/1912-04-16/ed-1/.

Where the look departs from it:

- UnifrakturMaguntia stands in for the title's blackletter, and the
  engraving between its words is left out; Fira Sans Condensed for the
  paper's gothics, Old Standard TT for its roman.
- The jump lines say "Continued on page 2." where the paper says
  "Continued on second page, fifth column."
- The page is 17½ × 26½ in, as the scan is; the columns end where
  their text does, where the paper fills them with the stories left
  out; the second page sets only the two stories that go on there.
- In HTML and EPUB the stories are in the table's cells, which a
  narrow screen squeezes; the decks and heads are centred by the look's
  CSS.
- In HTML and EPUB the jump lines are worded by the story they go on
  in ("Continued in …", "Continued from …"), an e-book having no pages
  of its own; the PDF by the page ("Continued on page 2.").
