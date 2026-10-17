"""What the scripts share: the work folder, the printing's page and its
table's geometry, measured from the scans (frame.py, compare.py)."""
import os

WORK = os.environ.get('BABBAGE_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/babbage'))
# The page: the Oxford copy's leaf (25 cm), the scans at about 567 ppi.
PAGE = (416.3, 708.7)
# The table's columns, their edges from the middle of the thick rule left
# of Num. (in points): the arcs', Num.'s, the logarithms' and Diff.'s;
# each figures' column's right edge where the figures end a point short
# of it on the scans (compare.py's medians over the twenty pages).
EDGES = [-39.5, -19.8, 0.1, 25.9, 63.41, 88.61, 113.74, 138.91, 164.11, 188.46, 213.71, 238.97, 264.08, 289.55, 334.6]
# The rules down the table, their middles from the thick rule's (the
# scans' medians; the figures' columns' edges, above, where the figures
# stand).
RULES = [-39.5, -19.8, 0.1, 27.1, 65.0, 90.1, 115.2, 140.3, 165.4, 190.5, 215.6, 240.7, 265.8, 291.6, 334.6]
# The table's outer edge, its first column of arcs wider on a recto.
OUTER = {'verso': -39.5, 'recto': -40.7}
# The thick rule's middle on the page, a verso's and a recto's (the
# scans' medians), and the rules across (the heads' and the foot's).
THICK = {'verso': 75.9, 'recto': 59.8}
HEAD_RULE, FOOT_RULE = 82.0, 628.2
