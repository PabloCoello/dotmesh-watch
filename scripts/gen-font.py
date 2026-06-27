#!/usr/bin/env python3
"""Genera una fuente bitmap Connect IQ (.fnt AngelCode + .png) desde un TTF.

Los glifos se renderizan en BLANCO sobre transparente: Connect IQ los tinta con
dc.setColor() al dibujar, así la misma fuente sirve para Paper, teal, etc.

Uso:  gen-font.py <ttf> <size_px> <charset> <out_basename>
Salida: resources/fonts/<out_basename>.{fnt,png}
"""
import os, sys, math
from PIL import Image, ImageDraw, ImageFont

ttf, size, charset, name = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUTDIR = os.path.join(ROOT, "resources", "fonts")
os.makedirs(OUTDIR, exist_ok=True)

font = ImageFont.truetype(ttf, size)
ascent, descent = font.getmetrics()
lineH = ascent + descent
adv = round(font.getlength("0"))           # monoespaciado: un solo avance
chars = list(dict.fromkeys(charset))        # únicos, conservando el orden

pad = 2
cellW, cellH = adv + pad, lineH + pad
cols = max(1, 1024 // cellW)
rows = math.ceil(len(chars) / cols)
atlasW, atlasH = cols * cellW, rows * cellH

img = Image.new("RGBA", (atlasW, atlasH), (255, 255, 255, 0))
draw = ImageDraw.Draw(img)
records = []
for i, ch in enumerate(chars):
    x = (i % cols) * cellW
    y = (i // cols) * cellH
    draw.text((x, y), ch, font=font, fill=(255, 255, 255, 255))
    records.append((ord(ch), x, y, adv, lineH))

img.save(os.path.join(OUTDIR, name + ".png"))

lines = [
    'info face="%s" size=%d bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=0,0'
    % (name, size),
    'common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0'
    % (lineH, ascent, atlasW, atlasH),
    'page id=0 file="%s.png"' % name,
    'chars count=%d' % len(records),
]
for cid, x, y, w, h in records:
    lines.append(
        'char id=%d x=%d y=%d width=%d height=%d xoffset=0 yoffset=0 xadvance=%d page=0 chnl=15'
        % (cid, x, y, w, h, w)
    )
with open(os.path.join(OUTDIR, name + ".fnt"), "w") as f:
    f.write("\n".join(lines) + "\n")

print("%s: %d glifos, avance=%d, atlas %dx%d" % (name, len(records), adv, atlasW, atlasH))
