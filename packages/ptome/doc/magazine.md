# The magazine website

A website whose text flow, typography and layout read like a print
magazine's: an issue's pieces written in AsciiDoc, each part of a piece
named by a role, set by a look (`doc/looks.md`) that follows an era of
print. No templates and no stylesheet of your own: name the look.

```asciidoc
= The Avalanche at Tunnel Creek: Sixteen skiers set out. What followed took less than a minute.
John Doe
:look: magazine-1970s
:lang: en
:figure-caption!:
:kicker: Mountains
:credit: Produced by Jane Roe • Photographed by John Doe
:issue: Vol. 12, No. 4

[.lede.dropcap]
[.dateline]#Stevens Pass, Wash. —# The snow came in the night …

[.pullquote]
____
It was the longest minute of my life.
____

.[.caption-lead]#The slope.# Looking up the chute from the runout.
image::slope.jpg[Slope,float=right]

[.columns]
== The science

…

[.end]
The last paragraph of the piece.
```

`:lang:` lets browsers hyphenate the justified text; `:figure-caption!:`
drops "Figure 1." from captions, which magazines don't number.

## The parts of a piece

The names follow the newsroom's (hed, dek, lede: spellings that began
as typesetting orders no one could mistake for copy) and map onto IPTC's
NITF and Apple News Format, so another output can take them.

| Part | Written as | NITF | Apple News Format |
| --- | --- | --- | --- |
| Kicker, the line above the head | `:kicker:` | (none) | `heading` above the title |
| Hed, the head | the document title | `hl1` | `title` |
| Dek (standfirst), the line under it | the title after `title-separator` (`: `), or a `[.dek]` paragraph | `hl2` | `intro` |
| Byline | the author line (`By ` before it) | `byline` | `byline` |
| Credit line | `:credit:` | (none) | `byline` |
| Issue line | `:issue:` | `pubdata` | `byline` |
| Dateline | `[.dateline]#Place —#` at the lede's start | `dateline` | part of `body` |
| Lede, the first paragraph | `[.lede]` | `p` (`lede`) | `body` |
| Initial (drop cap) | `[.dropcap]` on the lede | | `dropCapStyle` |
| Subhead | a section title | `hl2` in the body | `heading2` |
| Pull quote | `[.pullquote]` on a quote block | `bq` | `pullquote` |
| Caption, its lead-in | an image's title; `[.caption-lead]#…#` | `media-caption` | `caption` |
| Sidebar | a sidebar block | `block` | `container` |
| Columns | `[.columns]` on a section | | `layout.columns` |
| End mark | after the last paragraph, or a paragraph's `[.end]` | | |
| Placement | `float=right` / `left` on an image | | `layout.columnStart` |

"Kicker" also names a story's punchy closing line; the closing flourish
here is the end mark, `[.end]`, so the word keeps one meaning.

## Eras

| Look | After | Its devices |
| --- | --- | --- |
| `magazine` | the mid-century general magazine (*Look*, 1955; *Scientific American*, 1957) | a letterspaced capital kicker, an italic Didone head, a dek in large text type, three justified columns in bounded sections, bold small-capital caption lead-ins, a square end mark |
| `magazine-1950s` | the fashion magazine (Brodovitch's *Harper's Bazaar*, Wolf's *Esquire*) | a hairline Didone centred in white space, a five-line initial, ragged text |
| `magazine-1960s` | the Swiss magazine (*Twen*, Vignelli) | a grotesque flush left, two sizes, type hung from 2 pt and ½ pt rules, two-column sections, no initial |
| `magazine-1970s` | the rock tabloid (*Rolling Stone*) | an Oxford-rule frame, slab heads, red italic pull quotes |
| `magazine-1980s` | the technical monthly (*BYTE*, *Creative Computing*) | a neo-grotesque, tinted sidebars, ruled listings, a dinkus (• • • •) for an end mark and a break |
| `broadsheet` | the classic broadsheet (the *New York Times*, 1976–2007) | a centred head between rules, six-column sections with hairlines between them |
| `compact` | the European compact (the *Guardian*, 2005 and 2018) | a slab head, five-column sections, `[.comment]` sections ranged left |

The faces are free stand-ins for the era's own, from Google Fonts (the
look's `webfonts`); a publication's licensed faces go in a look that
extends the era (`font.text.family`, its `webfonts` or `css:`
`@font-face`). Never imitate a publication's real nameplate: the head is
the piece's own.

## An issue as a website

An issue is a document whose sections are its pieces, set as linked
pages (`ptome -b multipage_html5 -a multipage-level=1 issue.adoc`): the
home page holds what comes before the first piece, each piece a page.
The magazine looks lay the links between pages out as a magazine's
furniture: the link on is a jump line ("Continued in The Last Lift
Operator →", `multipage-nav-next-template`), and between the links a
folio ("Mountain Quarterly · Vol. 12, No. 4 · 2",
`multipage-nav-folio-template`, from the title, `:issue:` and the
page's place). Any of them is the document's to change, as an attribute.

## How it is laid out

The page is a grid of twelve units: the head across ten, the text across
eight (`--mag-body-span`), images and pull quotes floated into the text
and running around it (`shape-outside`). A long piece stays one column:
in Dyson and Kipping's study a single column read fastest, and columns
on a screen make readers scroll down one and back up for the next. So
columns are for bounded sections, `[.columns]`, a head and any image
spanning them. At a phone's width everything is one column, floats sit
in the text and columns go.

Each device has a fallback: `initial-letter` (Chrome, Safari) falls back
to a floated letter (Firefox), `text-wrap: pretty` and `balance` to
greedy breaking, `hyphens: auto` (with `:lang:`) to ragged lines.

## An era of your own

An era is a look that extends `magazine` and sets its tokens (faces,
sizes, colors, `rule.major` and `rule.minor`) and these custom
properties, in its `css:`:

| Property | What it sets | `magazine`'s |
| --- | --- | --- |
| `--mag-grid-units`, `--mag-gutter`, `--mag-body-span` | the grid, its gutter, the text's span | `12`, `1.5rem`, `8` |
| `--mag-head-align`, `--mag-display-style` | the head's alignment and style | `start`, `italic` |
| `--mag-kicker-case`, `--mag-kicker-tracking` | the kicker's capitals and their spacing | `uppercase`, `.14em` |
| `--mag-dropcap-lines` | the initial's depth, in lines | `3` |
| `--mag-frame-width`, `--mag-frame-gap` | a thick-and-thin frame around the page (`0`: none) | `0px`, `0px` |
| `--mag-end-mark` | the end mark | `"\25A0"` (■) |
| `--mag-section-columns`, `--mag-column-min` | `[.columns]` sections' columns, their narrowest | `3`, `14rem` |
| `--mag-text-align` | the text's alignment | `justify` |

```yaml
extends: magazine
tokens:
  font:
    display: { family: { screen: Playfair Display }, weight: bold }
  color: { accent: '#8A1C1C' }
webfonts:
  - Playfair Display:400,700
css: |
  :root{--mag-frame-width:4px;--mag-frame-gap:3px;--mag-dropcap-lines:4}
```

The PDF edition of an issue is partly the engine's work still: its
`[.columns]` sections are set in balanced columns, `[.dropcap]`
paragraphs with their own initial and `[.pullquote]`s floated with the
text running around them already (`columns_count`, `role: dropcap:
drop_lines`, `role: pullquote: float` in each era's `pdf:`), and a
piece whose section role has page keys is set on pages of its own (its
margins, a tint or an image behind it, no running content:
`section: role: <role>: page_background_color` and the like in `pdf:`;
`doc/pdf.md`). In
print, the magazine looks keep the base theme's faces.
