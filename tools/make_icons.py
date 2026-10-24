"""Génère les icônes de l'application (utilisé pendant la construction)."""
import os
import numpy as np
from PIL import Image, ImageDraw

C1, C2 = (108, 77, 255), (176, 108, 255)
SS = 4


def gradient(w, h):
    y, x = np.mgrid[0:h, 0:w]
    t = (x / w + y / h) / 2
    arr = np.zeros((h, w, 4), dtype=np.uint8)
    for i in range(3):
        arr[..., i] = (C1[i] + (C2[i] - C1[i]) * t).astype(np.uint8)
    arr[..., 3] = 255
    return Image.fromarray(arr, "RGBA")


def motif(canvas, cx, cy, u):
    d = ImageDraw.Draw(canvas)
    P = lambda x, y: (cx + x * u, cy + y * u)
    d.rounded_rectangle([*P(-34, -30), *P(34, 30)], radius=7 * u, fill=(255, 255, 255, 255))
    d.rounded_rectangle([*P(-28, -24), *P(28, 24)], radius=3 * u, fill=(207, 195, 255, 255))
    sx, sy = P(14, -10)
    d.ellipse([sx - 6 * u, sy - 6 * u, sx + 6 * u, sy + 6 * u], fill=(255, 209, 102, 255))
    d.polygon([P(-27, 23), P(-10, -8), P(8, 23)], fill=(142, 120, 255, 255))
    d.polygon([P(-4, 23), P(12, 2), P(27, 23)], fill=(90, 63, 224, 255))
    star = [(0, -16), (3.5, -3.5), (16, 0), (3.5, 3.5), (0, 16), (-3.5, 3.5), (-16, 0), (-3.5, -3.5)]
    pts = [P(28 + a * 0.75, -27 + b * 0.75) for a, b in star]
    d.polygon(pts, fill=(255, 209, 102, 255), outline=(108, 77, 255, 255), width=int(1.2 * u))


def render(size, bg, u_ratio, offset=(0, 0)):
    big = size * SS
    img = gradient(big, big) if bg else Image.new("RGBA", (big, big), (0, 0, 0, 0))
    motif(img, big / 2 + offset[0] * SS, big / 2 + offset[1] * SS, big * u_ratio)
    return img.resize((size, size), Image.LANCZOS)


os.makedirs("assets/icon", exist_ok=True)
render(1024, True, 0.0105, (0, 8)).convert("RGB").save("assets/icon/icon.png")
render(1024, False, 0.0072, (0, 6)).save("assets/icon/icon_foreground.png")
print("icônes générées")
