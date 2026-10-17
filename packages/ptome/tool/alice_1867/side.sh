#!/bin/sh
# A PDF page beside its scan: side.sh BOOK-LEAF PDF-PAGE OUT.png
W=${ALICE_WORK:-$HOME/.cache/asciidart-work/alice-match}
T=$(mktemp -d)
pdftoppm -r 80 -f "$2" -l "$2" -png "$W/build/alice/alice.pdf" "$T/p"
python3 -c "
import glob
from PIL import Image
a=Image.open(glob.glob('$T/p*.png')[0]); b=Image.open('$W/throughlookinggl01carr_650/%04d.jpg'%$1)
b=b.resize((int(b.width*a.height/b.height), a.height))
o=Image.new('RGB',(a.width+b.width,a.height),'white'); o.paste(a,(0,0)); o.paste(b,(a.width,0)); o.save('$3')"
rm -rf "$T"
