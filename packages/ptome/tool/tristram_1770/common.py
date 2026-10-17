"""What the scripts share: the work folder, the scan's item, its pixels a
point, the printed page's measure."""
import os

WORK = os.environ.get('TRISTRAM_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/tristram'))
ITEM = '10931855bsb'

# (The leaf: 1,818 pixels tall on the scan; the octavo's leaf, 175 mm,
# its pixels a point.)
PAGE = (306.0, 496.0)
PX = 1818 / PAGE[1]

# (The type: Libre Caslon Text at SIZE on the octavo's PITCH (61.3
# pixels of the scan line to line), its lines MEASURE wide (771 pixels);
# the footnotes at NOTE on NOTE_PITCH.)
MEASURE = 210.4
SIZE = 10.4
PITCH = 16.73
NOTE = 8.8
# (The dedication in a larger size.)
DEDICATION = 12.0
NOTE_PITCH = 14.0

# (The page's text in the PDF: its left edge on a recto and on a verso
# (the inner and outer margins), the head's baseline. A leaf's pixels set
# on the page by its text's left edge and its head's baseline.)
PAGE_PT = (306.0, 496.0)
LEFT = {'recto': 42.0, 'verso': 53.6}
HEAD = 50.5


def side(leaf):
    return 'recto' if int(leaf) % 2 == 0 else 'verso'
