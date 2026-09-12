#!/usr/bin/env python3
"""
Generate adaptive-icon VectorDrawable XML from one logic template.

Launcher icons cannot tint at runtime on the home screen — Android only
switches discrete activity-alias resources. Buckets are ~10% steps;
charge state uses a yellow bolt from the same generator logic.
"""
from __future__ import annotations

import math
from pathlib import Path

app_res = Path(r"d:\Xuyingjie_wb\Downloads\magisk\QSC-Battery\app\app\src\main\res")
drawable = app_res / "drawable"
mipmap = app_res / "mipmap-anydpi-v26"
drawable.mkdir(parents=True, exist_ok=True)
mipmap.mkdir(parents=True, exist_ok=True)

# Fewer buckets was tried; restore ~10% steps (calendar-style).
# 11 levels × 2 styles × 2 charge = 44 vectors (still generated from one template).
LEVELS = list(range(0, 101, 10))
BOLT_IDLE = "#095C42"
BOLT_CHG = "#FFC107"  # yellow when charging

BAT_BX0, BAT_BY0, BAT_BX1, BAT_BY1 = 38.0, 32.0, 70.0, 78.0
BAT_INSET = 3.5
TIP = (46.0, 26.0, 62.0, 34.0)


def bat_fill_top(ratio: float) -> float:
    ratio = max(0.0, min(1.0, float(ratio)))
    inner_top = BAT_BY0 + BAT_INSET
    inner_bot = BAT_BY1 - BAT_INSET
    h = inner_bot - inner_top
    if ratio <= 0.02:
        return inner_bot
    return inner_bot - max(h * ratio, 2.0)


def vector_wrap(paths: str) -> str:
    return (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
        '    android:width="108dp"\n'
        '    android:height="108dp"\n'
        '    android:viewportWidth="108"\n'
        '    android:viewportHeight="108">\n'
        f"{paths}"
        "</vector>\n"
    )


def path(d: str, color: str, fill_alpha: float | None = None) -> str:
    alpha = ""
    if fill_alpha is not None:
        alpha = f'\n        android:fillAlpha="{fill_alpha}"'
    return (
        f'    <path\n'
        f'        android:fillColor="{color}"{alpha}\n'
        f'        android:pathData="{d}" />\n'
    )


def round_rect_path(x0, y0, x1, y1, r) -> str:
    r = min(r, (x1 - x0) / 2, (y1 - y0) / 2)
    return (
        f"M{x0 + r},{y0} H{x1 - r} Q{x1},{y0} {x1},{y0 + r} "
        f"V{y1 - r} Q{x1},{y1} {x1 - r},{y1} H{x0 + r} "
        f"Q{x0},{y1} {x0},{y1 - r} V{y0 + r} Q{x0},{y0} {x0 + r},{y0} Z"
    )


def bolt_path(cx, cy, s=1.0) -> str:
    pts = [
        (cx + 5 * s, cy - 30 * s),
        (cx - 15 * s, cy + 1 * s),
        (cx - 1 * s, cy + 1 * s),
        (cx - 9 * s, cy + 30 * s),
        (cx + 17 * s, cy - 5 * s),
        (cx + 3 * s, cy - 5 * s),
    ]
    d = f"M{pts[0][0]:.2f},{pts[0][1]:.2f} "
    d += " ".join(f"L{x:.2f},{y:.2f}" for x, y in pts[1:])
    return d + " Z"


def arc_ring_path(cx, cy, r, sweep_deg, stroke=5.0) -> str:
    if sweep_deg <= 0.5:
        return ""
    sweep_deg = min(359.9, sweep_deg)
    r_out = r + stroke / 2
    r_in = max(0.5, r - stroke / 2)
    start = -90.0
    end = start + sweep_deg

    def pt(rad, ang):
        a = math.radians(ang)
        return cx + rad * math.cos(a), cy + rad * math.sin(a)

    large = 1 if sweep_deg > 180 else 0
    x0, y0 = pt(r_out, start)
    x1, y1 = pt(r_out, end)
    xi1, yi1 = pt(r_in, end)
    xi0, yi0 = pt(r_in, start)
    return (
        f"M{x0:.3f},{y0:.3f} "
        f"A{r_out:.3f},{r_out:.3f} 0 {large} 1 {x1:.3f},{y1:.3f} "
        f"L{xi1:.3f},{yi1:.3f} "
        f"A{r_in:.3f},{r_in:.3f} 0 {large} 0 {xi0:.3f},{yi0:.3f} Z"
    )


def make_battery(fill_ratio: float, charging: bool) -> str:
    bolt = BOLT_CHG if charging else BOLT_IDLE
    parts = []
    parts.append(path("M54,22 a32,36 0 1,1 0,72 a32,36 0 1,1 0,-72 Z", "#FFFFFF", 0.08))
    tx0, ty0, tx1, ty1 = TIP
    parts.append(path(round_rect_path(tx0, ty0, tx1, ty1, 3.5), "#FFFFFF"))
    parts.append(path(round_rect_path(BAT_BX0, BAT_BY0, BAT_BX1, BAT_BY1, 8), "#FFFFFF"))
    parts.append(
        path(
            f"M{BAT_BX0 + 3:.1f},{BAT_BY0 + 6:.1f} H{BAT_BX0 + 7:.1f} "
            f"V{BAT_BY1 - 12:.1f} H{BAT_BX0 + 3:.1f} Z",
            "#FFFFFF",
            0.28,
        )
    )
    fill_top = bat_fill_top(fill_ratio)
    inner_bot = BAT_BY1 - BAT_INSET
    if fill_ratio > 0.02 and fill_top < inner_bot - 0.5:
        parts.append(
            path(
                round_rect_path(BAT_BX0 + BAT_INSET, fill_top, BAT_BX1 - BAT_INSET, inner_bot, 5.5),
                "#7EECBE",
            )
        )
        if fill_ratio >= 0.15 or charging:
            cy = (fill_top + inner_bot) / 2
            parts.append(path(bolt_path(54, cy, s=0.32), bolt))
    elif charging:
        parts.append(path(bolt_path(54, 58, s=0.32), bolt))
    return vector_wrap("".join(parts))


def make_alt(fill_ratio: float, charging: bool) -> str:
    bolt = BOLT_CHG if charging else "#FFFFFF"
    parts = []
    parts.append(path("M54,24 a30,30 0 1,1 0,60 a30,30 0 1,1 0,-60 Z", "#2EC896", 0.16))
    parts.append(
        path(
            arc_ring_path(54, 54, 28, 359.9, stroke=4.5)
            or "M54,25.5 A28.5,28.5 0 1 1 53.99,25.5 Z",
            "#FFFFFF",
            0.18,
        )
    )
    sweep = 359.9 * max(0.0, min(1.0, fill_ratio))
    arc = arc_ring_path(54, 54, 28, sweep, stroke=4.5)
    if arc:
        parts.append(path(arc, "#7EECBE"))
    parts.append(path("M54,38 a16,16 0 1,1 0,32 a16,16 0 1,1 0,-32 Z", "#24AF82"))
    parts.append(path(bolt_path(54, 54, s=0.48), bolt))
    return vector_wrap("".join(parts))


def write_adaptive(name: str, fg: str, mono: str, bg: str):
    (mipmap / f"{name}.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        f'    <background android:drawable="@color/{bg}" />\n'
        f'    <foreground android:drawable="@drawable/{fg}" />\n'
        f'    <monochrome android:drawable="@drawable/{mono}" />\n'
        "</adaptive-icon>\n",
        encoding="utf-8",
    )


def main():
    # purge old 10%-step / non-chg launcher vectors
    for p in drawable.glob("ic_launcher_fg_bat_*.xml"):
        p.unlink()
    for p in drawable.glob("ic_launcher_fg_alt_*.xml"):
        p.unlink()
    for p in mipmap.glob("ic_launcher_bat_*.xml"):
        p.unlink()
    for p in mipmap.glob("ic_launcher_alt_*.xml"):
        p.unlink()

    (drawable / "ic_launcher_fg.xml").write_text(make_battery(0.6, False), encoding="utf-8")
    (drawable / "ic_launcher_fg_alt.xml").write_text(make_alt(0.7, False), encoding="utf-8")
    write_adaptive("ic_launcher", "ic_launcher_fg", "ic_launcher_monochrome", "ic_launcher_bg")
    write_adaptive(
        "ic_launcher_alt", "ic_launcher_fg_alt", "ic_launcher_monochrome_alt", "ic_launcher_bg_alt"
    )

    for lv in LEVELS:
        ratio = lv / 100.0
        for chg in (False, True):
            suf = f"{lv:02d}" + ("_chg" if chg else "")
            bat_fg = f"ic_launcher_fg_bat_{suf}"
            alt_fg = f"ic_launcher_fg_alt_{suf}"
            (drawable / f"{bat_fg}.xml").write_text(make_battery(ratio, chg), encoding="utf-8")
            (drawable / f"{alt_fg}.xml").write_text(make_alt(ratio, chg), encoding="utf-8")
            write_adaptive(
                f"ic_launcher_bat_{suf}",
                bat_fg,
                "ic_launcher_monochrome",
                "ic_launcher_bg",
            )
            write_adaptive(
                f"ic_launcher_alt_{suf}",
                alt_fg,
                "ic_launcher_monochrome_alt",
                "ic_launcher_bg_alt",
            )

    print("ok levels=", LEVELS, "chg_bolt=", BOLT_CHG)


if __name__ == "__main__":
    main()
