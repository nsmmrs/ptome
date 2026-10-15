---
title: "Poor Richard's Almanack"
source: poor-richard.adoc
looks: [poor-richard]
compare:
  - page: 1
    scan: https://archive.org/download/poorrichardalman00fran/page/n0.jpg
    note: "The title page (1733, in the 1849 facsimile)"
  - page: 5
    scan: https://archive.org/download/poorrichardalman00fran/page/n8.jpg
    note: "January: its verse and its calendar, the signs among the figures, the proverbs down the last column"
  - page: 11
    scan: https://archive.org/download/poorrichardalman00fran/page/n14.jpg
    note: "July (the almanac's fifth month)"
---

# Poor Richard's Almanack

The first Poor Richard's Almanack, for 1733, in a look after its
facsimile: the title page, Richard Saunders's address to the Courteous
Reader (Franklin's prediction of Titan Leeds's death), the Anatomy of
Man's Body with its woodcut and the characters of the planets and the
aspects, the Explanation of the almanac and its Profitable
Observations, and the twelve months. What the work shows: dense tables
in small type — each month a page of its own, headed by its number in
the almanac's year (March is the first) between rules, its verse, then
its calendar in seven columns ruled apart, a line to each day: the day
of the month and of the week (G, the Sunday letter), the Church's days,
the planets' aspects and the weather, the time of high water, the
Moon's place in the zodiac, the Sun's rising and setting, and the
lunations with the proverbs running down the last column in italic;
the signs of the zodiac, the planets and the aspects (♈ ☉ ☌ ⚹ □ △) set
among the figures from symbol fonts, counted as the text's own font so
that a line with a sign is no taller than the others
(`font_fallback_metrics: base`, FEAT-ml7z96); a tagged PDF whose
first heading is H1 although the book has no title page of ptome's
(BUG-ljj0fk) (FEAT-7h00dm).

## Sources

| What | Where | SHA-256 |
| --- | --- | --- |
| `text/` | transcribed for the work from the facsimile, Philadelphia, George S. Appleton, [1849?], https://archive.org/details/poorrichardalman00fran (the University of North Carolina's copy; scans n0–n19) | |
| The anatomy's woodcut, the facsimile's scan | in `fetch.yml` with its SHA-256 | in `fetch.yml` |

The facsimile reproduces the almanac Benjamin Franklin printed for 1733
"in nearly the same style as that in which it was first published"
(its publisher's note, left out with his advertisement and the planets'
motions, the table of kings, the eclipses, the chronology, the courts
and fairs and the roads). The transcription keeps its words, spelling,
capitals, italics, abbreviations and punctuation; it writes the round s
for its long s, and each sign by its name (`{aries}`), the characters
in `text/signs.adoc`.

## Licence

The almanac is in the public domain (published 1732 for 1733; Franklin
died in 1790); so is the facsimile (published about 1849). The
transcription is the work's own (MIT, as the repository). The scans are
not committed: `tool/showcase.dart` fetches the woodcut and the pages
it compares into its cache.

## Fonts

Libre Caslon Text, Noto Sans Symbols and Noto Sans Symbols 2 (the
signs, the planets, the aspects), Noto Serif (all SIL Open Font License
1.1), from Google Fonts: `ptome doctor --look poor-richard --looksdir
test/showcase/poor-richard` installs them. Not committed.

## The printing the look follows

The facsimile, Philadelphia, George S. Appleton, [1849?], scanned by
the Internet Archive, https://archive.org/details/poorrichardalman00fran.

Where the look departs from it:

- Libre Caslon Text stands in for the facsimile's old-style roman; the
  signs are Noto's, sans serif, where the facsimile's are its own.
- The frames of rules around each page are left out, and the headings
  of the front matter are set at the left, where the facsimile centres
  them; the woodcut's labels are a table beside its signs.
- In the excerpt test, the signs are written as their names: none of
  the fonts the tests commit has them.
- In HTML and EPUB, the signs come from the reader's fonts.
