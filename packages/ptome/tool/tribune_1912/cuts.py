"""The cuts the work sets cut from the scan (regions.txt's `cut`
regions): written as JPEGs into the folder given (a build's images; the
showcase's fetch.yml has them from the Library of Congress's image
service).

    python3 -I cuts.py DIR
"""
import os, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK, IMAGES
from lines import regions


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for page, rs in regions().items():
        im = None
        for rid, kind, box in rs:
            if kind != 'cut':
                continue
            path = os.path.join(out, f'{rid}.jpg')
            if os.path.exists(path):
                continue
            im = im or Image.open(os.path.join(WORK, IMAGES[page] + '.jpg'))
            im.crop(box).save(path, quality=90)


main()
