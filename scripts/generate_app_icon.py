#!/usr/bin/env python3
"""Generates the SmartAirKey app icon (1024x1024, no alpha).

Design: a white key with radiating proximity waves on a blue gradient — the
app's "seamless, hands-free access" identity, using the accent blue (#327BF9).

Rendered at 4x supersampling then downscaled for crisp, anti-aliased edges.
Run from the repo root:  python3 scripts/generate_app_icon.py
"""

import math
import os

from PIL import Image, ImageDraw

OUT = "SmartAirKey/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
FINAL = 1024
SS = 4                      # supersampling factor
S = FINAL * SS             # working canvas size

# Accent blue (matches Assets.xcassets AccentColor) and a darker shade.
LIGHT = (86, 156, 255)     # top-left, lighter blue
DARK = (24, 78, 196)       # bottom-right, deeper blue
WHITE = (255, 255, 255)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def make_background():
    """Diagonal blue gradient with a soft top-left highlight, built small and
    upscaled so it stays smooth without a slow per-pixel loop at full size."""
    g = FINAL  # build gradient at final resolution, then upscale to S
    bg = Image.new("RGB", (g, g))
    px = bg.load()
    maxd = (g - 1) * 2
    for y in range(g):
        for x in range(g):
            t = (x + y) / maxd            # 0 (top-left) .. 1 (bottom-right)
            r, gr, b = lerp(LIGHT, DARK, t)
            # Soft radial highlight near the upper-left for depth.
            dx, dy = (x - g * 0.32), (y - g * 0.30)
            dist = math.hypot(dx, dy) / (g * 0.9)
            glow = max(0.0, 0.18 * (1.0 - dist))
            r = min(255, round(r + glow * 255))
            gr = min(255, round(gr + glow * 255))
            b = min(255, round(b + glow * 255))
            px[x, y] = (r, gr, b)
    return bg.resize((S, S), Image.LANCZOS)


def make_key_layer():
    """Draws the key + proximity waves horizontally on a transparent layer,
    then rotates it diagonally (bow to the upper-left, teeth to lower-right)."""
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    cy = S * 0.5
    bow_cx = S * 0.36
    bow_outer = S * 0.150
    bow_inner = S * 0.078
    shaft_th = S * 0.072

    # Proximity waves: arcs centred on the bow, opening to the left, at
    # decreasing opacity — the "hands-free / seamless" signal.
    for i, radius in enumerate((S * 0.205, S * 0.255, S * 0.305)):
        alpha = (150, 105, 65)[i]
        w = S * 0.030
        box = (bow_cx - radius, cy - radius, bow_cx + radius, cy + radius)
        d.arc(box, start=128, end=232, fill=WHITE + (alpha,), width=round(w))

    # Key bow (ring): filled outer circle, punch the hole out afterwards.
    d.ellipse((bow_cx - bow_outer, cy - bow_outer,
               bow_cx + bow_outer, cy + bow_outer), fill=WHITE + (255,))

    # Shaft.
    shaft_x0 = bow_cx + bow_outer * 0.35
    shaft_x1 = S * 0.760
    d.rounded_rectangle((shaft_x0, cy - shaft_th / 2, shaft_x1, cy + shaft_th / 2),
                        radius=shaft_th * 0.35, fill=WHITE + (255,))

    # Teeth (two downward prongs near the shaft end).
    tooth_w = S * 0.060
    tooth_h = S * 0.085
    for tx in (shaft_x1 - S * 0.150, shaft_x1 - S * 0.045):
        d.rounded_rectangle((tx, cy + shaft_th / 2 - S * 0.004,
                             tx + tooth_w, cy + shaft_th / 2 + tooth_h),
                            radius=tooth_w * 0.30, fill=WHITE + (255,))

    # Punch the bow hole (transparent) so it reads as a ring.
    hole = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    hd = ImageDraw.Draw(hole)
    hd.ellipse((bow_cx - bow_inner, cy - bow_inner,
                bow_cx + bow_inner, cy + bow_inner), fill=WHITE + (255,))
    # Clear the hole area from the layer.
    r, g, b, a = layer.split()
    hr, hg, hb, ha = hole.split()
    from PIL import ImageChops
    a = ImageChops.subtract(a, ha)
    layer = Image.merge("RGBA", (r, g, b, a))

    # Rotate diagonally and keep centred.
    layer = layer.rotate(-40, resample=Image.BICUBIC, center=(S / 2, S / 2))
    return layer


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bg = make_background()
    key = make_key_layer()

    # Soft drop shadow for the key so it lifts off the gradient.
    from PIL import ImageFilter
    shadow = key.split()[3].point(lambda v: int(v * 0.45))
    shadow_img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow_img.putalpha(shadow)
    black = Image.new("RGBA", (S, S), (10, 30, 70, 0))
    black.putalpha(shadow)
    black = black.filter(ImageFilter.GaussianBlur(S * 0.012))
    off = round(S * 0.010)
    bg = bg.convert("RGBA")
    bg.alpha_composite(black, (off, off))
    bg.alpha_composite(key)

    icon = bg.convert("RGB").resize((FINAL, FINAL), Image.LANCZOS)
    icon.save(OUT, "PNG")
    print(f"Wrote {OUT} ({icon.size[0]}x{icon.size[1]}, mode={icon.mode})")


if __name__ == "__main__":
    main()
