---
title: "The Book of Common Prayer"
source: bcp.adoc
looks: [bcp]
compare:
  - page: 2
    scan: https://archive.org/download/10904662bsb/page/n23.jpg
    note: "The Calendar's January with its table of lessons, the red-letter days in red (Cambridge, 1761)"
  - page: 4
    scan: https://archive.org/download/10904662bsb/page/n48.jpg
    note: "Morning Prayer: its opening and its first rubrics (1761)"
---

# The Book of Common Prayer

The Calendar, Morning Prayer, the Litany and the Psalter of the Book of
Common Prayer (1662), in red and black, in a look after the octavo John
Baskerville printed at Cambridge in 1760–61. What the work shows: two
colours (the rubrics, the red-letter days, the heads and the verse
numbers in red, the rest in black), liturgical layout (versicles and
responses run in after their speakers, the Litany's responses printed
from its units scheme, never written after each petition), the Psalter
pointed for chanting and numbered by verse, quoted whole as a work of
its own, initials opening each office, and the calendar's January as a
ruled table (FEAT-v9bhk3).

## Sources

| What | Where |
| --- | --- |
| Morning Prayer, the Litany | the units corpus, `test/units/corpus/liturgy/bcp-1662/` (its `NOTICE.md` gives their sources), included without their headers |
| The Psalter | the same, quoted whole (`include::psalter[unit="1-150",cite=none]`), Coverdale's translation pointed for singing, transcribed by Lynda M. Howell (public domain text) |
| The Calendar's January | `text/calendar.adoc`, transcribed for the work from the 1761 printing below |
| `schemes/liturgy.yml` | a copy of the units corpus's scheme (the document reads the schemes beside it) |

## The scans transcribed

The pages of https://archive.org/details/10904662bsb the transcription was
made from, each the Internet Archive's JPEG
(`https://archive.org/download/10904662bsb/page/<page>.jpg`) with its
SHA-256:

```
803c24fd960fb610bf773ccbc5955141ae4cc38ea10c112abce0558ee1517205  n23.jpg
```

## Licence

The Book of Common Prayer (1662) is in the public domain in the United
States and under life plus 70 years. (In the United Kingdom the Crown's
letters patent still govern the Prayer Book's printing; the texts here
are the corpus's transcriptions, used under its terms.) The
transcription of the calendar and the arrangement are the work's own
(MIT, as the repository).

## Fonts

Libre Baskerville, and Noto Serif for the versicle sign (SIL Open Font
License 1.1), from Google Fonts: `ptome doctor --look bcp --looksdir
test/showcase/bcp` installs them. Not committed.

## The printing the look follows

The Book of Common Prayer, Cambridge: John Baskerville, 1761, the
Bayerische Staatsbibliothek's copy:
https://archive.org/details/10904662bsb

## Where it departs from it

- Baskerville's octavo is in black alone, its rubrics and red-letter days
  in italic; the red is from the Prayer Books printed in red and black
  (the folio of 1662 and its successors).
- The calendar is January's alone, without the other months.
- The texts are the corpus's transcriptions, their spelling modern; a
  few of the corpus's rubrics are headings there ("The people shall
  answer here…"), and are set as headings here.
