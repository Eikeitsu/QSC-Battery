from PIL import Image, ImageDraw
from pathlib import Path

out = Path(r"C:\Users\Xuyingjie_wb\.cursor\projects\d-Xuyingjie-wb-Downloads-magisk\assets")
app_res = Path(
    r"d:\Xuyingjie_wb\Downloads\magisk\QSC-Battery\app\app\src\main\res"
)
out.mkdir(parents=True, exist_ok=True)


def lerp(a, b, t):
    return int(a + (b - a) * t)


def radial_bg(size, c0, c1):
    """Soft radial gradient from center-top."""
    img = Image.new("RGBA", (size, size))
    px = img.load()
    cx, cy = size * 0.5, size * 0.42
    max_r = size * 0.78
    for y in range(size):
        for x in range(size):
            dx, dy = x - cx, y - cy
            t = min(1.0, (dx * dx + dy * dy) ** 0.5 / max_r)
            t = t * t
            px[x, y] = (
                lerp(c0[0], c1[0], t),
                lerp(c0[1], c1[1], t),
                lerp(c0[2], c1[2], t),
                255,
            )
    return img


def bolt_poly(cx, cy, s=1.0):
    return [
        (cx + 5 * s, cy - 30 * s),
        (cx - 15 * s, cy + 1 * s),
        (cx - 1 * s, cy + 1 * s),
        (cx - 9 * s, cy + 30 * s),
        (cx + 17 * s, cy - 5 * s),
        (cx + 3 * s, cy - 5 * s),
    ]


def make_primary(size=1080):
    # richer green radial
    img = radial_bg(size, (18, 140, 100), (8, 78, 56))
    d = ImageDraw.Draw(img)

    # soft spotlight behind battery
    spot = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(spot).ellipse((300, 220, 780, 880), fill=(255, 255, 255, 22))
    img = Image.alpha_composite(img, spot)
    d = ImageDraw.Draw(img)

    bx0, by0, bx1, by1 = 385, 245, 695, 825
    # white battery body
    d.rounded_rectangle((bx0, by0, bx1, by1), radius=78, fill=(255, 255, 255, 255))
    # tip
    d.rounded_rectangle((475, 185, 605, 265), radius=30, fill=(255, 255, 255, 255))

    # glass sheen on left of body
    sheen = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).rounded_rectangle(
        (bx0 + 22, by0 + 36, bx0 + 78, by1 - 90),
        radius=28,
        fill=(255, 255, 255, 70),
    )
    img = Image.alpha_composite(img, sheen)
    d = ImageDraw.Draw(img)

    inset = 30
    fill_top = by0 + int((by1 - by0) * 0.40)
    # mint charge with soft top
    d.rounded_rectangle(
        (bx0 + inset, fill_top, bx1 - inset, by1 - inset),
        radius=48,
        fill=(126, 236, 190, 255),
    )
    # secondary lighter band at top of fill
    band = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(band).rounded_rectangle(
        (bx0 + inset, fill_top, bx1 - inset, fill_top + 54),
        radius=48,
        fill=(190, 250, 220, 90),
    )
    img = Image.alpha_composite(img, band)
    d = ImageDraw.Draw(img)

    cy = fill_top + (by1 - inset - fill_top) // 2 - 6
    d.polygon(bolt_poly(540, cy, s=3.35), fill=(9, 92, 66, 255))
    return img


def make_alt(size=1080):
    img = radial_bg(size, (12, 70, 55), (3, 28, 22))
    d = ImageDraw.Draw(img)

    # soft glow disc
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((240, 240, 840, 840), fill=(46, 200, 150, 40))
    img = Image.alpha_composite(img, glow)
    d = ImageDraw.Draw(img)

    # main mint disc with slight radial via overlay
    d.ellipse((310, 310, 770, 770), fill=(36, 175, 130, 255))
    highlight = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(highlight).ellipse((350, 330, 620, 560), fill=(255, 255, 255, 38))
    img = Image.alpha_composite(img, highlight)
    d = ImageDraw.Draw(img)

    d.polygon(bolt_poly(540, 535, s=5.4), fill=(255, 255, 255, 255))
    return img


def squircle_preview(src, radius=240):
    s = src.size[0]
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, s - 1, s - 1), radius=radius, fill=255)
    preview = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    preview.paste(src, (0, 0), mask)
    return preview


primary = make_primary()
alt = make_alt()
squircle_preview(primary).save(out / "qsc-icon-preview-primary.png")
squircle_preview(alt).save(out / "qsc-icon-preview-alt.png")

densities = {
    "drawable-xxxhdpi": 432,
    "drawable-xxhdpi": 324,
    "drawable-xhdpi": 216,
    "drawable-hdpi": 162,
    "drawable-mdpi": 108,
}
for folder, px in densities.items():
    dest = app_res / folder
    dest.mkdir(parents=True, exist_ok=True)
    primary.resize((px, px), Image.Resampling.LANCZOS).save(dest / "ic_launcher_fg.png")
    alt.resize((px, px), Image.Resampling.LANCZOS).save(dest / "ic_launcher_fg_alt.png")

print("ok")
