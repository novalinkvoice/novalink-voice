"""Run from tool/: writes icon.png / foreground.png / background.png next to this
script; copy them to assets/icon/ and run `dart run flutter_launcher_icons`.
nova-swirl.png = the swirl path from project-website/flyers/novalink-logo.svg,
recoloured cyan #15e8ff, rendered at 2000 px with Inkscape.

NovaLink Voice launcher icon v2: the NovaLink 'nova' swirl (from the logo SVG)
behind a handset, on the brand purple gradient."""
import os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

S = 1024
HERE = os.path.dirname(os.path.abspath(__file__))
PURPLE_DEEP, PURPLE = (0x3D, 0x0F, 0x6E), (0x72, 0x00, 0xBC)
FONT = os.path.expanduser("~/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf")
HANDSET = ""   # Material 'call_rounded'
SWIRL = Image.open(os.path.join(HERE, "nova-swirl.png")).convert("RGBA")   # cyan, transparent bg


def gradient():
    g = Image.new("RGB", (S, S)); px = g.load()
    for y in range(S):
        for x in range(S):
            t = (x + y) / (2 * S)
            px[x, y] = tuple(int(PURPLE_DEEP[i] + (PURPLE[i] - PURPLE_DEEP[i]) * t) for i in range(3))
    return g.convert("RGBA")


def swirl(width_frac):
    w = int(S * width_frac); h = int(SWIRL.height * w / SWIRL.width)
    sw = SWIRL.resize((w, h), Image.LANCZOS)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    layer.alpha_composite(sw, ((S - w) // 2, (S - h) // 2))
    return layer


def handset(px, fill, outline=None, stroke=0):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    f = ImageFont.truetype(FONT, px)
    bb = d.textbbox((0, 0), HANDSET, font=f, stroke_width=stroke)
    w, h = bb[2] - bb[0], bb[3] - bb[1]
    pos = ((S - w) / 2 - bb[0], (S - h) / 2 - bb[1])
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sh).text((pos[0] + 8, pos[1] + 12), HANDSET, font=f, fill=(20, 0, 45, 150),
                            stroke_width=stroke, stroke_fill=(20, 0, 45, 150))
    layer = Image.alpha_composite(layer, sh.filter(ImageFilter.GaussianBlur(14)))
    ImageDraw.Draw(layer).text(pos, HANDSET, font=f, fill=fill, stroke_width=stroke,
                               stroke_fill=outline or fill)
    return layer


def build(variant, swirl_w, phone_px, stroke):
    if variant == "white":
        ph = handset(phone_px, (255, 255, 255, 255), PURPLE_DEEP + (255,), stroke)
    else:
        ph = handset(phone_px, PURPLE_DEEP + (255,), (255, 255, 255, 255), stroke)
    return ph


def main(variant="white"):
    bg = gradient()
    full = Image.alpha_composite(bg, swirl(0.98))
    full = Image.alpha_composite(full, build(variant, 0.98, 470, 22))
    # Adaptive foreground: Android crops to ~66 % centre, so shrink the art.
    fg = Image.alpha_composite(swirl(0.82), build(variant, 0.82, 400, 19))
    return bg, full, fg


if __name__ == "__main__":
    mask = Image.new("L", (S, S), 0); ImageDraw.Draw(mask).ellipse([0, 0, S, S], fill=255)
    prev = Image.new("RGBA", (980, 260), (245, 244, 250, 255))
    for i, v in enumerate(["white", "purple"]):
        bg, full, fg = main(v)
        if v == (sys.argv[1] if len(sys.argv) > 1 else "white"):
            full.convert("RGB").save(os.path.join(HERE, "icon.png"))
            fg.save(os.path.join(HERE, "foreground.png"))
            bg.convert("RGB").save(os.path.join(HERE, "background.png"))
        for j, img in enumerate([full, Image.alpha_composite(bg, fg)]):
            t = img.copy(); t.putalpha(mask)
            prev.alpha_composite(t.resize((200, 200), Image.LANCZOS), (30 + (i * 2 + j) * 235, 30))
    prev.save(os.path.join(HERE, "preview2.png"))
    print("ok")
