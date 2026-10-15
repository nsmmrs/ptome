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

## The scans transcribed

The pages of https://archive.org/details/poorrichardalman00fran the transcription was
made from, each the Internet Archive's JPEG
(`https://archive.org/download/poorrichardalman00fran/page/<page>.jpg`) with its
SHA-256:

```
5a2d2c85aa65919c87068dfa1470eb1483564cac1c2dd35a8eaa517da5d1c1e5  n0.jpg
14dc11aaa3ddd3bbf805fa63a1e400da9bf3e96d6f9034667bda1bbd3ad380e3  n3.jpg
132d5bc43f76e9bc4e9c221766b7ba2a82be0423f61a1b62616e2fcb8c7529f3  n4.jpg
ab5f01418b425db98616e222149044817a4adac340dd7e8b209456c526d6841b  n6.jpg
80b339a1409b3f13a10ea0e0c9488f9f063722e0c095bf3f6b3ab35a7636d675  n8.jpg
98e7c859a0fc4730350e9aabf9402ea3381d63b8b64baaa5d37ae7589e2d46a2  n9.jpg
da4b5bd238b98e8ddd7ff6603ae624b3f6c5a0a8e8d7fa357f6411d24b36c934  n10.jpg
6e10ccf3119bc2f53da9f43ac9036d9cc7af9819731e43f5f5ca17e13f954a45  n11.jpg
e5f4b139c97bcc1435b2f258e87301f59a76c9546324c5fb1a42d27028b27f9e  n12.jpg
67f832a027e74e32668511ea7541570b7d1d65157a4e796282a82cfedca92473  n13.jpg
95d73c342f33b3d4380d8992d2b4398bfc9c9d38d6f51f1aea7bf2cca722db4b  n14.jpg
7a5bf0b43c90afde6a1b3b140b3c1887537b0157180a2cfa8ce2df297ff51511  n15.jpg
4064c69b5c34a2d2ed2bcf3375986537555a1c1c6c96a1cb907178d0439f8631  n16.jpg
b5d49faaf5205b89bd896b479453433b14527719c591ab4a7dbd5fe5c5ecd6a3  n17.jpg
3d4294d09557d9f77047bcc3591123b61e44dd790f10f9cfe3b7a024fb3967e7  n18.jpg
485ed1fbc39e813cb31c9044a49af66e45a261818a0afee19fe5d49f7b4e7215  n19.jpg
```

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
