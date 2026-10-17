"""The lines still flagged read once more, each alone: its band of the
scan (its box, a little more) cut, made twice its size and read by
Tesseract as one line (segmentation 7); the choice of the line's
readings (confirm.py's: the transcription's side, or the OCR's where it
but spells the word otherwise) whose letters are that reading's, all
but a letter or two, taken. Writes draft.json again; the readings kept
in TRISTRAM_WORK/lineread.json, by leaf and box.

    python3 -I lineread.py
"""
import difflib, json, os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import WORK
from confirm import choices, key


def read(job):
    leaf, box = job
    im = Image.open(os.path.join(WORK, 'png', f'{leaf:04d}.png')).convert('L')
    x0, y0, x1, y1 = box
    im = im.crop((max(0, x0 - 20), max(0, y0 - 8), min(im.width, x1 + 20), min(im.height, y1 + 8)))
    im = im.resize((im.width * 2, im.height * 2), Image.LANCZOS)
    path = os.path.join(WORK, 'lineread', f'{leaf:04d}-{y0}.png')
    im.save(path)
    env = dict(os.environ, OMP_THREAD_LIMIT='1')
    return subprocess.run(['tesseract', path, '-', '-l', 'eng', '--psm', '7'],
                          capture_output=True, text=True, env=env).stdout.strip()


def main():
    draft = json.load(open(os.path.join(WORK, 'draft.json')))
    cache_path = os.path.join(WORK, 'lineread.json')
    cache = json.load(open(cache_path)) if os.path.exists(cache_path) else {}
    os.makedirs(os.path.join(WORK, 'lineread'), exist_ok=True)
    todo = []
    for v in draft.values():
        for l in v['lines']:
            k = f"{v['leaf']}:{','.join(map(str, l['box']))}"
            if l['flag'] and l['box'][2] > l['box'][0] and k not in cache:
                todo.append((k, (v['leaf'], l['box'])))
    with ThreadPoolExecutor(8) as ex:
        for (k, _), got in zip(todo, ex.map(read, [j for _, j in todo])):
            cache[k] = got
    json.dump(cache, open(cache_path, 'w'))
    settled = 0
    for v in draft.values():
        for l in v['lines']:
            k = f"{v['leaf']}:{','.join(map(str, l['box']))}"
            if not l['flag'] or k not in cache:
                continue
            o = key(cache[k])
            if len(o) < 6:
                continue
            best, arg = 0, None
            for c in choices(l['text']):
                r = difflib.SequenceMatcher(None, key(c), o, autojunk=False).ratio()
                if r > best:
                    best, arg = r, c
            if arg is not None and best >= 0.96 and abs(len(key(arg)) - len(o)) <= 2:
                l['text'] = re.sub(r'\s+', ' ', arg).strip()
                l['flag'] = False
                l['confirmed'] = round(best, 3)
                settled += 1
    json.dump(draft, open(os.path.join(WORK, 'draft.json'), 'w'), indent=0)
    print(settled, 'lines settled by a reading of their own;',
          sum(l['flag'] for v in draft.values() for l in v['lines']), 'still flagged')


if __name__ == '__main__':
    main()
