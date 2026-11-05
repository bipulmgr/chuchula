#!/usr/bin/env python3
"""Draws the Chuchula app icon and writes every size Android, iOS and the
stores need. Run from the repo root: python3 scripts/generate_icons.py
(needs Pillow and the DejaVu fonts)."""
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 1024
FELT_C = (22, 113, 75)
FELT_E = (7, 51, 31)
GOLD = (224, 179, 84)
GOLD_SOFT = (243, 223, 162)
CREAM = (250, 246, 234)
RED = (192, 38, 45)
INK = (24, 24, 28)
SUIT_FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
RANK_FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf'


def felt(size):
    """Radial green felt."""
    im = Image.new('RGB', (size, size), FELT_E)
    px = im.load()
    c = size / 2
    for y in range(size):
        for x in range(size):
            d = min(1.0, math.hypot(x - c, y - c) / (size * 0.72))
            px[x, y] = tuple(int(FELT_C[i] * (1 - d) + FELT_E[i] * d) for i in range(3))
    return im


def card(w, h, rank, suit, color):
    im = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    r = int(w * 0.12)
    d.rounded_rectangle([0, 0, w - 1, h - 1], r, fill=CREAM, outline=GOLD, width=max(2, w // 40))
    rf = ImageFont.truetype(RANK_FONT, int(w * 0.30))
    sf_small = ImageFont.truetype(SUIT_FONT, int(w * 0.24))
    sf_big = ImageFont.truetype(SUIT_FONT, int(w * 0.62))
    d.text((w * 0.10, h * 0.04), rank, font=rf, fill=color)
    d.text((w * 0.12, h * 0.04 + w * 0.32), suit, font=sf_small, fill=color)
    d.text((w / 2, h * 0.58), suit, font=sf_big, fill=color, anchor='mm')
    return im


def fan(size, scale=1.0):
    """Three fanned cards centered on a transparent square."""
    layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    w, h = int(size * 0.36 * scale), int(size * 0.50 * scale)
    cards = [('K', '♠', INK, -24), ('A', '♥', RED, 0), ('Q', '♦', RED, 24)]
    cx, cy = size / 2, size * 0.56
    for rank, suit, color, angle in cards:
        c = card(w, h, rank, suit, color)
        # Pivot near the bottom so the cards fan out from one point.
        big = Image.new('RGBA', (w * 3, h * 3), (0, 0, 0, 0))
        big.paste(c, (w, int(h * 0.6)))
        rot = big.rotate(-angle, resample=Image.BICUBIC, center=(w * 1.5, h * 0.6 + h * 0.95))
        shadow = rot.split()[3].filter(ImageFilter.GaussianBlur(size * 0.012))
        sh = Image.new('RGBA', rot.size, (0, 0, 0, 0))
        sh.putalpha(shadow.point(lambda a: int(a * 0.45)))
        ox = int(cx - w * 1.5)
        oy = int(cy - (h * 0.6 + h * 0.95) + h * 0.45 * scale / scale)
        layer.alpha_composite(sh, (ox + int(size * 0.008), oy + int(size * 0.014)))
        layer.alpha_composite(rot, (ox, oy))
    # The fan leans right and sits low: center its visible part.
    box = layer.getbbox()
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.alpha_composite(layer, (int((size - box[2] - box[0]) / 2), int((size - box[3] - box[1]) / 2)))
    return out


def ring(im, inset, width):
    d = ImageDraw.Draw(im)
    s = im.size[0]
    d.ellipse([inset, inset, s - inset, s - inset], outline=GOLD, width=width)
    d.ellipse([inset + width * 1.6, inset + width * 1.6, s - inset - width * 1.6, s - inset - width * 1.6],
              outline=GOLD_SOFT + (150,), width=max(1, width // 3))


def full_icon():
    im = felt(S).convert('RGBA')
    ring(im, S * 0.07, int(S * 0.018))
    im.alpha_composite(fan(S, 0.92))
    return im.convert('RGB')


def adaptive_foreground():
    # Android crops adaptive icons to the middle 66%: keep the art inside.
    fg = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    art = fan(S, 0.92)
    small = art.resize((int(S * 0.70), int(S * 0.70)), Image.LANCZOS)
    fg.alpha_composite(small, ((S - small.width) // 2, (S - small.height) // 2))
    return fg


def save(im, path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.resize((size, size), Image.LANCZOS).save(path)


def main():
    icon = full_icon()
    os.makedirs('store', exist_ok=True)
    icon.save('store/icon-1024.png')
    save(icon, 'store/play-icon-512.png', 512)

    # Android legacy and round icons.
    dens = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
    res = 'android/app/src/main/res'
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, S, S], fill=255)
    round_icon = icon.convert('RGBA')
    round_icon.putalpha(mask)
    for d, px in dens.items():
        save(icon, f'{res}/mipmap-{d}/ic_launcher.png', px)
        save(round_icon, f'{res}/mipmap-{d}/ic_launcher_round.png', px)
        # Adaptive foreground is 108dp.
        save(adaptive_foreground(), f'{res}/mipmap-{d}/ic_launcher_foreground.png', int(px * 108 / 48))

    # iOS: no transparency allowed.
    ios = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    for name in os.listdir(ios):
        if name.endswith('.png'):
            px = Image.open(os.path.join(ios, name)).size[0]
            save(icon, os.path.join(ios, name), px)

    # Play Store feature graphic 1024x500.
    fg = felt(1024).resize((1024, 500)).convert('RGBA')
    art = fan(S, 0.92).resize((460, 460), Image.LANCZOS)
    fg.alpha_composite(art, (40, 20))
    d = ImageDraw.Draw(fg)
    title = ImageFont.truetype('assets/fonts/YatraOne-Regular.ttf', 104)
    sub = ImageFont.truetype('assets/fonts/Mukta-SemiBold.ttf', 40)
    d.text((520, 180), 'Chuchula', font=title, fill=GOLD, anchor='lm')
    d.text((528, 290), 'चुचुला · Nepali card game', font=sub, fill=GOLD_SOFT, anchor='lm')
    fg.convert('RGB').save('store/feature-graphic-1024x500.png')


if __name__ == '__main__':
    main()
