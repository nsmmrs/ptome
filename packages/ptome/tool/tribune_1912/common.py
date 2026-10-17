"""What the scripts share: the work folder, the pages (the scan's image
sequence numbers), the scan's resolution."""
import os

WORK = os.environ.get('TRIBUNE_WORK', os.path.expanduser('~/.cache/asciidart-work/print-match/tribune'))

# (The pages the work sets, by the issue's page number: Chronicling
# America's sequence numbers and the Library of Congress's image files.)
PAGES = {1: 1, 2: 2}
IMAGES = {1: '0303', 2: '0304'}

# (The scan's pixels a point: 400 to the inch, as its ALTO's units have it.)
PX = 400 / 72
