"""The words of a rendered page near given heights: python3 -I words.py PDF PAGE Y..."""
import re, subprocess, sys
xml = subprocess.run(['pdftotext', '-f', sys.argv[2], '-l', sys.argv[2], '-bbox', sys.argv[1], '-'], capture_output=True, text=True).stdout
ws = re.findall(r'xMin="([\d.]+)" yMin="[\d.]+" xMax="[\d.]+" yMax="([\d.]+)">([^<]*)<', xml)
for y in sys.argv[3:]:
    print(y, [(round(float(x)), w) for x, b, w in ws if abs(float(b) - float(y)) < 1.5])
