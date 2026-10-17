"""The look's `lh<tenths>` roles for the pitches the draft's stanzas use
(transcribe.py's `leads:` line), written between the look's `lh-begin`
and `lh-end` lines: python3 -I leads.py LOG LOOK"""
import re, sys
log, look = sys.argv[1], sys.argv[2]
used = set(re.findall(r'\blh(\d+)\b', open(log).read()))
used.update(('130', '157'))  # (the mirrored stanza's, set by a patch; the closing poem's, conclusion.adoc)
roles = ''.join(f'      lh{n}: {{ line_height: {int(n) / 118.4:.4f} }}\n' for n in sorted(used, key=int))
s = open(look).read()
s = re.sub(r'(      # lh-begin\n).*?(      # lh-end\n)', lambda m: m[1] + roles + m[2], s, flags=re.S)
open(look, 'w').write(s)
