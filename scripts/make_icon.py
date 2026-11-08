"""Rysuje ikonę aplikacji (1024 px) tak samo jak LogoMark w Kit.swift.

Uruchom: python3 scripts/make_icon.py
iOS sam zaokrągla rogi ikony, więc tło wypełnia cały kwadrat.
"""
import math
from PIL import Image, ImageDraw

OUT = "Terminy/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
S = 1024
K = 4  # nadpróbkowanie dla gładkich krawędzi
N = S * K
TOP, BOTTOM = (0x19, 0xC3, 0xA6), (0x1E, 0x6F, 0xD9)
DOT = (0xFF, 0xC9, 0x4D)


def gradient():
    small = Image.new("RGB", (256, 256))
    px = small.load()
    for y in range(256):
        for x in range(256):
            t = (x + y) / 510
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM))
    return small.resize((N, N), Image.BICUBIC).convert("RGBA")


img = gradient()
layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
d = ImageDraw.Draw(layer)
c = N / 2
r = N * 0.31
w = N * 0.075
box = [c - r - w / 2, c - r - w / 2, c + r + w / 2, c + r + w / 2]
sweep = 0.82 * 360
# tor łuku
d.arc(box, 0, 360, fill=(255, 255, 255, 56), width=round(w))
# łuk odliczania od godziny 12 zgodnie z ruchem wskazówek
d.arc(box, -90, -90 + sweep, fill=(255, 255, 255, 255), width=round(w))
# zaokrąglone końce łuku
for ang in (-90, -90 + sweep):
    a = math.radians(ang)
    x, y = c + r * math.cos(a), c + r * math.sin(a)
    d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=(255, 255, 255, 255))
# złota kropka na końcu
a = math.radians(-90 + sweep)
x, y = c + r * math.cos(a), c + r * math.sin(a)
dr = N * 0.065
d.ellipse([x - dr, y - dr, x + dr, y + dr], fill=DOT + (255,))
# „T”
bar_w, bar_h = N * 0.26, N * 0.075
stem_w, stem_h = N * 0.085, N * 0.25
top_y = c - N * 0.125
rad = bar_h / 2
d.rounded_rectangle([c - bar_w / 2, top_y, c + bar_w / 2, top_y + bar_h], radius=rad, fill="white")
d.rounded_rectangle([c - stem_w / 2, top_y, c + stem_w / 2, top_y + stem_h], radius=stem_w / 2, fill="white")

img = Image.alpha_composite(img, layer).resize((S, S), Image.LANCZOS).convert("RGB")
img.save(OUT)
print("zapisano", OUT)
