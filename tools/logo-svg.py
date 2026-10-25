"""Turn device/bin/k4logo's k4draw commands into an SVG, so the README logo matches the device exactly.

    sh device/bin/k4logo 0 0 1 name | python tools/logo-svg.py > docs/images/logo.svg
"""
import sys

PAD = 6
out = []
for line in sys.stdin:
    f = line.split()
    if not f:
        continue
    if f[0] == 'fill':
        x, y, w, h, g = map(int, f[1:6])
        out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="rgb({g},{g},{g})"/>')
    elif f[0] == 'rect':  # k4draw draws the outline inside the box, t px thick
        x, y, w, h, g, t = map(int, f[1:7])
        out.append(f'<rect x="{x + t / 2}" y="{y + t / 2}" width="{w - t}" height="{h - t}" fill="none" '
                   f'stroke="rgb({g},{g},{g})" stroke-width="{t}"/>')
    elif f[0] in ('text', 'ctext'):  # (x, y) = top-left of the line (ctext: x = centre); size in px
        x, y, size, g = map(int, f[1:5])
        text = ' '.join(f[5:])
        anchor = ' text-anchor="middle"' if f[0] == 'ctext' else ''
        out.append(f'<text x="{x}" y="{y + size * 0.8:.0f}"{anchor} font-family="Helvetica, Arial, sans-serif" '
                   f'font-size="{size}" fill="rgb({g},{g},{g})">{text}</text>')

# canvas: the device (150x210), taller if there's text below it
bottom = max([210] + [int(l.split('y="')[1].split('"')[0]) + 8 for l in out if l.startswith('<text')])
w, h = 150 + 2 * PAD, bottom + 2 * PAD
print(f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="{-PAD} {-PAD} {w} {h}">')
print(f'<rect x="{-PAD}" y="{-PAD}" width="{w}" height="{h}" fill="white"/>')
print('\n'.join(out))
print('</svg>')
