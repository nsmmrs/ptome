"""Parse an Internet Archive hOCR file into pages of lines with word boxes."""
import re, html, json, sys

def parse(path):
    text = open(path, encoding='utf-8').read()
    pages = []
    for pm in re.finditer(r"<div class=['\"]ocr_page['\"][^>]*title=['\"]([^'\"]*)['\"][^>]*>(.*?)(?=<div class=['\"]ocr_page|\Z)", text, re.S):
        title, body = pm.group(1), pm.group(2)
        bbox = [int(v) for v in re.search(r'bbox (\d+) (\d+) (\d+) (\d+)', title).groups()]
        lines = []
        for lm in re.finditer(r"<span class=['\"]ocr_(?:line|caption|textfloat|header)['\"][^>]*title=['\"]([^'\"]*)['\"][^>]*>(.*?)</span>\s*(?=<span class=['\"]ocr_(?:line|caption|textfloat|header)|</p>|</div>)", body, re.S):
            lt, lb = lm.group(1), lm.group(2)
            lbox = [int(v) for v in re.search(r'bbox (\d+) (\d+) (\d+) (\d+)', lt).groups()]
            words = []
            for wm in re.finditer(r"<span class=['\"]ocrx_word['\"][^>]*title=['\"]([^'\"]*)['\"][^>]*>(.*?)</span>", lb, re.S):
                wt = wm.group(1)
                wbox = [int(v) for v in re.search(r'bbox (\d+) (\d+) (\d+) (\d+)', wt).groups()]
                conf = re.search(r'x_wconf (\d+)', wt)
                w = html.unescape(re.sub(r'<[^>]+>', '', wm.group(2)))
                words.append({'t': w, 'b': wbox, 'c': int(conf.group(1)) if conf else None})
            if words:
                lines.append({'b': lbox, 'w': words})
        pages.append({'b': bbox, 'lines': lines})
    return pages

if __name__ == '__main__':
    pages = parse(sys.argv[1])
    json.dump(pages, open(sys.argv[2], 'w'))
    print(len(pages), 'pages')
