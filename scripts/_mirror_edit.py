"""Break or restore the supplier page's price markup.

The break empties only the price field and leaves the row container and the product
name intact. That matters: an earlier, more destructive break renamed the row container
too, so extraction returned ZERO rows and `scraper heal` timed out at 600s with nothing
to anchor on. A field going null while the page still parses is both the truer failure
mode and something heal can actually reason about.
"""
import re, sys

PATH = 'mirror/index.html'
s = open(PATH).read()

if sys.argv[1:2] == ['break']:
    s2, n = re.subn(r'<div class="price">\$([\d.]+)</div>',
                    r'<div class="price"><span data-amount="\1"></span></div>', s)
    print(f'  emptied {n} price nodes (rows + product names left intact)')
else:
    s2, n = re.subn(r'<div class="price"><span data-amount="([\d.]+)"></span></div>',
                    r'<div class="price">$\1</div>', s)
    print(f'  restored {n} price nodes')

open(PATH, 'w').write(s2)
