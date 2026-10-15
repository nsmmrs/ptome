---
title: "Moby-Dick; or, The Whale"
source: moby-dick.adoc
looks: [moby-dick]
compare:
  - page: 2
    scan: https://archive.org/download/mobydickorwhale01melv/page/n10.jpg
    note: "The dedication to Hawthorne (Harper & Brothers, 1851)"
  - page: 6
    scan: https://archive.org/download/mobydickorwhale01melv/page/n18.jpg
    note: "Extracts: quotations with their sources at the right (1851)"
  - page: 30
    scan: https://archive.org/download/mobydickorwhale01melv/page/n42.jpg
    note: "Chapter III: a chapter running on under its head (1851)"
---

# Moby-Dick; or, The Whale

Herman Melville's novel, whole, in a look after Harper & Brothers' first
American edition. What the work shows: scale (135 chapters and the
apparatus, 617 pages; `tool/showcase.dart` prints how long each
conversion takes), a novel's apparatus (the dedication on a page of its
own, the Etymology and the Extracts' quotations with their sources at
the right, the chapters' epigraphs, the footnotes), the play-script
chapters (*Midnight, Forecastle*: speakers and stage directions), and
widows, orphans and running heads over hundreds of pages.

## Sources

| What | Where | SHA-256 |
| --- | --- | --- |
| Moby-Dick, Standard Ebooks | https://github.com/standardebooks/herman-melville_moby-dick at `013b51e2d9d6bb28b1d054bfc30beeeff4b85480` (the `codeload.github.com` tarball) | `1059bceeb87ae492fe036aa499023572955fc1a1c1a4e82abf5c2cb4d13025bf` |
| Queequeg's mark (SVG, Standard Ebooks) | the same repository, in `fetch.yml` with its SHA-256 | in `fetch.yml` |

Imported by `tool/showcase_import.dart`, then edited:

- `moby-dick.adoc`: the title as the book has it; the chapters numbered
  in upper-case Roman numerals from Chapter I, the front matter and the
  epilogue not.
- `text/dedication.adoc`: an untitled section on a page of its own,
  centred (the importer of the time lost Standard Ebooks' untitled
  section; it keeps one now).

## Licence

The novel is in the public domain (published in 1851). Standard Ebooks
dedicates its production to the public domain (CC0 1.0); its own pages
and logo are left out, and its name is used only in this credit.

## Fonts

Old Standard TT for the Scotch modern the book was set in, and Noto
Serif Hebrew for the Etymology's Hebrew (both SIL Open Font License
1.1), from Google Fonts: `ptome doctor --look moby-dick --looksdir
test/showcase/moby-dick` installs them. Not committed.

## The printing the look follows

Moby-Dick; or, The Whale, New York: Harper & Brothers, 1851 (the first
American edition): https://archive.org/details/mobydickorwhale01melv

## Where it departs from it

- The text is Standard Ebooks' (the first American edition's, its
  spelling modernized where Standard Ebooks does).
- The Extracts' sources are set as a quotation's attribution, on a line
  of their own at the right; the book runs a short one in after the
  quotation's last words.
- The Etymology's words in the languages are a two-column table without
  rules.
