"""The Mouse's Tale as the 1867 printing sets it (leaf 53, page 37): each
line its words, the size of its type (from the x-height of its letters
on the scan) and where it starts (its left edge on the scan, from the
text's edge). Writes the verse block; its first line shares the
paragraph's last line ("this:——"), as the printing sets it."""

LEFT = 185          # the leaf's text edge
SIZES = {'a': 11.2, 'b': 9.5, 'c': 8.7, 'd': 8.1, 'e': 7.6, 'f': 6.4, 'g': 5.3, 'h': 4.4}
LINES = [
    ('a', 590, '“‘Fury said to'),
    ('b', 785, 'a mouse, That'),
    ('b', 1116, 'he met'),
    ('b', 1193, 'in the'),
    ('b', 1238, 'house,'),
    ('c', 1157, '‘Let us'),
    ('c', 1112, 'both go'),
    ('c', 1070, 'to law:'),
    ('c', 982, '__I__ will'),
    ('c', 784, 'prosecute'),
    ('c', 732, '__you__.—'),
    ('d', 767, 'Come, I’ll'),
    ('d', 858, 'take no'),
    ('d', 932, 'denial;'),
    ('d', 1050, 'We must'),
    ('d', 1274, 'have a'),
    ('d', 1421, 'trial:'),
    ('e', 1515, 'For'),
    ('e', 1414, 'really'),
    ('e', 1356, 'this'),
    ('e', 1389, 'morning'),
    ('e', 1565, 'I’ve'),
    ('e', 1424, 'nothing'),
    ('e', 1355, 'to do.’'),
    ('f', 1253, 'Said the'),
    ('f', 1179, 'mouse to'),
    ('f', 1156, 'the cur,'),
    ('f', 1208, '‘Such a'),
    ('f', 1337, 'trial,'),
    ('f', 1229, 'dear sir,'),
    ('f', 1105, 'With no'),
    ('g', 1017, 'jury or'),
    ('g', 983, 'judge,'),
    ('g', 1014, 'would be'),
    ('g', 1079, 'wasting'),
    ('g', 1115, 'our breath.’'),
    ('g', 1201, '‘I’ll be'),
    ('g', 1163, 'judge,'),
    ('g', 1105, 'I’ll be'),
    ('g', 1057, 'jury,’'),
    ('g', 1020, 'Said'),
    ('g', 1059, 'cunning'),
    ('g', 1146, 'old Fury;'),
    ('h', 1225, '‘I’ll try'),
    ('h', 1262, 'the whole'),
    ('h', 1325, 'cause,'),
    ('h', 1372, 'and'),
    ('h', 1293, 'condemn'),
    ('h', 1269, 'you'),
    ('h', 1241, 'to'),
    ('h', 1260, 'death.’”'),
]
BASE = 3.5          # the block's own size: its spaces, a point each


def block(margin_top):
    out = [f'[verse.tale%unbreakable,margin-top={margin_top:.1f}pt,margin-bottom=0]',
           '____']
    for group, x, text in LINES:
        spaces = round((x - LEFT) * 72 / 650 / (0.28 * BASE))
        out.append(' ' * spaces + f'[.tale-{group}]#{text}#')
    out += ['____', '// end::tale[]']
    return '\n'.join(out)
