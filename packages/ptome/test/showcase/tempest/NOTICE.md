---
title: "The Tempest"
source: tempest.adoc
looks: [tempest, folio]
compare:
  - page: 2
    look: folio
    scan: https://archive.org/download/mrvvilliamshakes00shak/page/n24.jpg
    note: "The First Folio's first page of the play: Act I, Scene I, and Scene II's start (1623)"
  - page: 3
    look: folio
    scan: https://archive.org/download/mrvvilliamshakes00shak/page/n26.jpg
    note: "Scene II going on, in two ruled columns (1623)"
---

# The Tempest

Shakespeare's The Tempest in two looks over one source: a modern reading
edition's (`tempest`) and the First Folio's (`folio`). What the work
shows: a play as description lists (each speech its speaker's), stage
directions as a role; the same text set in two ways, by the look alone;
in the modern look, a verse line shared between two speakers stepped so
that its parts read as one line (`role_<role>_text_indent: continue`,
FEAT-d1sdfw), each scene's lines numbered every fifth, the heads, names
and directions not counted and a shared line counted once
(`line_numbers_restart_level`, `line_numbers_skip_*`); in the Folio's,
two ruled columns in a frame of rules, speech prefixes run in, set in a
little from the lines after them (`description_list_term_indent`).

## Sources

| What | Where | SHA-256 |
| --- | --- | --- |
| The Tempest, Standard Ebooks (the Globe text, modernized) | https://github.com/standardebooks/william-shakespeare_the-tempest at `8e9859938331d3b324f1bf29cc23a5fd0703dc50` (the `codeload.github.com` tarball) | `8b693d2ec3a0260e8e51e54e66b23f6f23eead9247e8fee598c2db883f432b65` |

Imported by `tool/showcase_import.dart` (each speech table a description
list, a row without a speaker a `[.direction]` paragraph, or a
`[.continued]` one where the speaker goes on after a direction), then
edited:

- `tempest.adoc`: the line numbers for the modern look only (`ifeval` on
  the look).
- 157 verse lines shared between two speakers marked `[.shared]##…##`.
  Standard Ebooks doesn't mark them: they were found by the test editors
  use, two short half-lines next to each other that make one line of
  verse (each half of eight syllables or fewer, the shorter of five or
  fewer, nine to eleven together), and may include a few that an
  editor would read otherwise.
- `images/folio-frame.svg`: the Folio's frame of rules, drawn for the
  work.

## Licence

The play is in the public domain (first printed in 1623). Standard
Ebooks dedicates its production to the public domain (CC0 1.0); its own
pages and logo are left out, and its name is used only in this credit.
The frame is the work's own (MIT, as the repository).

## Fonts

- The modern look: EB Garamond (SIL Open Font License 1.1).
- The Folio's: IM Fell DW Pica (SIL Open Font License 1.1), the Fell
  types digitized by Igino Marini.

Both from Google Fonts, installed by `ptome doctor --look tempest
--looksdir test/showcase/tempest` and `--look folio`. Not committed.

## The printing the Folio look follows

Mr. William Shakespeares Comedies, Histories, & Tragedies, London:
Isaac Jaggard and Ed. Blount, 1623 (the First Folio), the Boston Public
Library's copy: https://archive.org/details/mrvvilliamshakes00shak

The modern look follows no one printing: it is designed after the
reading editions (the Folger's speakers on a line of their own and its
stepped shared lines; the line numbers every fifth by scene, as the
Oxford and the Arden count them).

## Where they depart

- The text is Standard Ebooks' modernized Globe text in both looks: the
  Folio's spelling, its long s, its abbreviated speech prefixes (*Pro.*,
  *Mir.*) and its Latin act and scene heads (*Actus primus, Scena
  prima.*) are a text's, not a look's.
- The Folio prints the cast ("Names of the Actors") at the play's end;
  here it comes first in both looks.
- The Folio runs a short direction (*Exit.*) in at the right of its
  line; here a direction in a speech follows its words.
- HTML and EPUB: a shared line is set in by a fixed amount (they can't
  measure the line before it), and the lines aren't numbered.
