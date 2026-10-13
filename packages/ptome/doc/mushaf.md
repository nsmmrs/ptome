# The Medina mushaf, line for line

The Medina mushaf (the King Fahd Complex's print of the Qur'an in the
Hafs reading) has 604 pages of 15 lines, and every copy has the same
words on the same line: a page ends at an ayah's end, and no ayah runs
across a page. `tool/mushaf.dart` sets it that way:

```sh
dart run tool/mushaf.dart          # into ~/.cache/asciidart-work/mushaf
cd ~/.cache/asciidart-work/mushaf
ptome -b pdf mushaf.adoc           # 604 pages, about 20 s
```

- **The data**: each word's page and line, and its text in the KFGQPC Hafs
  encoding, from the quran.com API (`/verses/by_page`); the surahs' Arabic
  names from `/chapters`. The lines no word is on are a surah's title and
  the basmala before it (none before at-Tawbah, and al-Fatiha's is its
  first ayah), in that order, even across a page's end.
- **The font**: KFGQPC Uthmanic Script Hafs (version 18), whose
  ligatures turn an ayah's number, in Arabic-Indic digits, into its
  medallion.
- **The document**: a page is a block of its lines, `<<<` between pages.
  The lines of verses are one paragraph, a hard break after each; a
  title and a basmala are centred paragraphs of their own; the first two
  pages' few lines are centred, as the mushaf sets them.
- **The theme** (`mushaf-theme.yml`, written beside it): an A5 page, a
  fixed line pitch that fills the text block with 15 lines, no space
  between paragraphs, and every line justified (`base_text_align_last:
  justify`), the last of a page and those before a hard break too.

The data and the font are the King Fahd Complex's, free to use but not
ours to redistribute, so they live in the cache and nothing of them is
committed; `test/pdf/mushaf_test.dart` sets the whole mushaf when they are
there (604 pages, no warning: a line too wide for the measure would wrap,
and its page run onto another) and is skipped when they aren't.

What the print has that this hasn't: the lines are justified by their
spaces alone, where the calligraphy lengthens letters (kashida) and picks
wider or narrower forms, so a line of few words shows wide gaps; the
surah titles are plain text, not framed cartouches; and the opening pages
have no ornamental frame.
