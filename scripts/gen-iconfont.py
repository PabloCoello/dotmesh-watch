#!/usr/bin/env python3
"""Genera la fuente de iconos de la powerline (.fnt AngelCode + .png) desde la
JetBrains Mono Nerd Font.

A diferencia de gen-font.py (monoespaciado: un solo avance para todos los
glifos), aquí cada icono se mide a su ANCHO REAL: las glifos de batería y de
actividad son anchos (doble celda en la Nerd Font) y un avance fijo los
recortaría.

Además REMAPEA cada glifo a un punto de la PUA del BMP (0xE0xx). El glifo de
actividad (md-pulse) vive en U+F05E9, fuera del BMP; algunos runtimes de
Connect IQ no resuelven fuentes bitmap por encima de U+FFFF, así que se empaqueta
con un id BMP estable y la esfera usa ese id.

Los glifos se renderizan en BLANCO sobre transparente: Connect IQ los tinta con
dc.setColor() al dibujar.

Uso:  gen-iconfont.py [size]   (size por defecto 26)
Salida: resources/fonts/jbmono_icons.{fnt,png}
"""
import os, sys, math
from PIL import Image, ImageDraw, ImageFont

SIZE = int(sys.argv[1]) if len(sys.argv) > 1 else 26
TTF = os.path.expanduser(
    "~/.local/share/fonts/JetBrainsMonoNerdFont/JetBrainsMonoNerdFont-Regular.ttf")
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUTDIR = os.path.join(ROOT, "resources", "fonts")
NAME = "jbmono_icons"
os.makedirs(OUTDIR, exist_ok=True)

# (id_destino_BMP, codepoint_fuente_NerdFont, etiqueta)
# Campana de contorno · batería por niveles (vacía→llena) · actividad (pasos).
ICONS = [
    (0xE000, 0xF0A2, "bell"),       # fa-bell-o
    (0xE001, 0xF244, "batt-empty"), # fa-battery-empty
    (0xE002, 0xF243, "batt-1"),     # fa-battery-quarter
    (0xE003, 0xF242, "batt-2"),     # fa-battery-half
    (0xE004, 0xF241, "batt-3"),     # fa-battery-three-quarters
    (0xE005, 0xF240, "batt-full"),  # fa-battery-full
    (0xE006, 0xF0583, "steps"),     # md-walk (figura andando = pasos)
]

font = ImageFont.truetype(TTF, SIZE)
ascent, descent = font.getmetrics()
lineH = ascent + descent

pad = 2
records = []  # (dst_id, x, y, w, h, xadvance)

# Ancho real por glifo: el máximo entre el avance tipográfico y el borde derecho
# de la tinta, para no recortar glifos anchos (batería/actividad).
cells = []
for dst, src, label in ICONS:
    ch = chr(src)
    adv = font.getlength(ch)
    box = font.getbbox(ch)  # (l, t, r, b) de la tinta
    right = box[2] if box else 0
    w = int(math.ceil(max(adv, right))) + 2
    cells.append((dst, src, label, w))

atlasW = sum(w for *_, w in cells) + pad * len(cells)
atlasH = lineH + pad
img = Image.new("RGBA", (atlasW, atlasH), (255, 255, 255, 0))
draw = ImageDraw.Draw(img)

x = 0
for dst, src, label, w in cells:
    draw.text((x, 0), chr(src), font=font, fill=(255, 255, 255, 255))
    records.append((dst, x, 0, w, lineH, w))
    x += w + pad

img.save(os.path.join(OUTDIR, NAME + ".png"))

lines = [
    'info face="%s" size=%d bold=0 italic=0 charset="" unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=0,0'
    % (NAME, SIZE),
    'common lineHeight=%d base=%d scaleW=%d scaleH=%d pages=1 packed=0'
    % (lineH, ascent, atlasW, atlasH),
    'page id=0 file="%s.png"' % NAME,
    'chars count=%d' % len(records),
]
for cid, x, y, w, h, adv in records:
    lines.append(
        'char id=%d x=%d y=%d width=%d height=%d xoffset=0 yoffset=0 xadvance=%d page=0 chnl=15'
        % (cid, x, y, w, h, adv)
    )
with open(os.path.join(OUTDIR, NAME + ".fnt"), "w") as f:
    f.write("\n".join(lines) + "\n")

print("%s: %d iconos, size=%d, atlas %dx%d" % (NAME, len(records), SIZE, atlasW, atlasH))
for dst, src, label, w in cells:
    print("  0x%04X <- U+%05X  %-10s  w=%d" % (dst, src, label, w))
