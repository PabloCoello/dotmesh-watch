"""Genera el launcher icon de la esfera: un 'mesh' 3x3 de acentos de sintaxis
sobre fondo Ink. Colores tomados de dotmesh/docs/DESIGN.md.

Uso (desde cualquier sitio):  python3 scripts/gen-icon.py
Salida: resources/drawables/launcher_icon.png
"""
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "resources", "drawables", "launcher_icon.png")

SIZE = 60  # launcher icon nativo del epix2pro47mm (evita el escalado 40->60)
INK_0 = (0x16, 0x17, 0x1B, 255)
EDGE = (0x2D, 0x2F, 0x36, 255)  # ink-3: aristas tenues del retículo

# 7 acentos de sintaxis + Paper + Graphite secundario = 9 nodos del mesh.
NODES = [
    (0xFF, 0xAA, 0x7A), (0xCB, 0xAA, 0xCB), (0x6C, 0xB6, 0xB0),
    (0x8F, 0xB4, 0xE3), (0xA8, 0xCB, 0xA0), (0xE3, 0xC5, 0x8A),
    (0xE5, 0x9A, 0x9A), (0xE9, 0xEA, 0xEC), (0x9A, 0x9D, 0xA4),
]
GRID = (SIZE // 4, SIZE // 2, 3 * SIZE // 4)  # retícula proporcional al tamaño

img = Image.new("RGBA", (SIZE, SIZE), INK_0)
d = ImageDraw.Draw(img)

# Aristas del retículo (el 'mesh').
for row in GRID:
    d.line([(GRID[0], row), (GRID[-1], row)], fill=EDGE, width=1)
for col in GRID:
    d.line([(col, GRID[0]), (col, GRID[-1])], fill=EDGE, width=1)

# Nodos: un punto por color.
r = max(3, SIZE // 14)
pts = [(x, y) for y in GRID for x in GRID]
for (px, py), c in zip(pts, NODES):
    d.ellipse([px - r, py - r, px + r, py + r], fill=c + (255,))

img.save(OUT)
print("launcher_icon.png generado (%dx%d) -> %s" % (SIZE, SIZE, OUT))
