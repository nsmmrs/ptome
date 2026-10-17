"""Whether an OCR's word spells a transcription's word otherwise."""
import difflib

SWAPS = {('’', 'e'), ('e', '’'), ('i', 'y'), ('y', 'i'), ('u', 'o'), ('o', 'u'), ('a', 'e'), ('e', 'a'),
         ('z', 's'), ('s', 'z'), ('k', 'c'), ('c', 'k')}


def variant(o, t):
    """Whether the OCR's word [o] is a spelling of the transcription's
    [t] (`scientifick` `scientific`, `endowed` `endow’d`, `chuse`
    `choose`), not another word misread (`thew` for `shew`, `arid` for
    `and`): letters let in or out, a letter or two at most, in a word of
    four or more, or swapped for its like."""
    if o == t:
        return True
    n = 0
    for op, a1, a2, b1, b2 in difflib.SequenceMatcher(None, o, t, autojunk=False).get_opcodes():
        if op == 'equal':
            continue
        if op in ('delete', 'insert') and (a2 == len(o) and b2 == len(t)) \
                and not set(o[a1:a2] + t[b1:b2]) <= set('ek’\''):
            return False
        if op == 'replace':
            if a2 - a1 != b2 - b1 or any((x, y) not in SWAPS for x, y in zip(o[a1:a2], t[b1:b2])):
                return False
        n += max(a2 - a1, b2 - b1)
    return n <= 2 and min(len(o), len(t)) >= 4
