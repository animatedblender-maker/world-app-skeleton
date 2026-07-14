#!/usr/bin/env python3
"""Horizon-arc icon: paper sky, ocean body, world map on the curved dome."""

from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
SCALE = 2
PAPER = (248, 246, 242)
INK = (44, 40, 37)
OCEAN = (238, 232, 216)
LAND = (46, 68, 84)

COLS, ROWS = 54, 28
MAP = [
    "......................................................",
    "......................................................",
    ".............########.................................",
    "............##########.............#####..............",
    "...........############...........#######.............",
    "..........##############.........#########............",
    ".........###############........###########...........",
    "........#################......#############..........",
    ".......#######....#######.....##############..........",
    "......########....########....###############.........",
    ".....#########.....########...#################.......",
    "....##########......########..#########..######.......",
    "...###########.......################...#######.......",
    "..############........##############....######........",
    ".##############........#############.....#####........",
    "##############..........############......####........",
    ".#############...........##########........###........",
    "..############............########.........##.........",
    "...###########.............######..........##.........",
    "....##########..............#####...........#.........",
    ".....#########..............#####...........##........",
    "......########..............######.........###........",
    ".......#######..............#######.......#####.......",
    "........######..............########.....#######......",
    ".........#####..............#########...#########.....",
    "..........####..............##########.###########....",
    "...........###..............#####################.....",
    "......................................................",
]
MAP = [r.ljust(COLS, ".")[:COLS] for r in MAP]

small = Image.new("L", (COLS, ROWS), 0)
sp = small.load()
for y, row in enumerate(MAP):
    for x, ch in enumerate(row):
        if ch == "#":
            sp[x, y] = 255
LAND_MASK = small.resize((COLS * 20, ROWS * 20), Image.Resampling.NEAREST)
MW, MH = LAND_MASK.size

OUT = Path(__file__).resolve().parents[1] / "WorldApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
PREVIEW = Path.home() / "Desktop/matterya_horizon_arc_icon.png"


def is_land(lat: float, lon: float) -> bool:
    row = int((90 - lat) / 180 * (MH - 1))
    col = int((lon + 180) / 360 * (MW - 1))
    return LAND_MASK.getpixel((max(0, min(MW - 1, col)), max(0, min(MH - 1, row)))) > 127


def render(scale: int) -> Image.Image:
    s = SIZE * scale
    cx, cy, radius = s * 0.5, s * 1.02, s * 0.78
    apex = cy - radius
    r2 = radius * radius
    map_lat_cutoff = -28

    img = Image.new("RGB", (s, s), PAPER)
    px = img.load()

    for y in range(s):
        for x in range(s):
            dx = x - cx
            dy = y - cy
            if dx * dx + dy * dy > r2:
                continue

            ndx = dx / radius
            ndy = (cy - y) / radius
            dz = math.sqrt(max(0.0, 1.0 - ndx * ndx - ndy * ndy))
            lat = math.degrees(math.asin(max(-1.0, min(1.0, ndy))))
            lon = math.degrees(math.atan2(ndx, dz))

            if lat < map_lat_cutoff:
                px[x, y] = OCEAN
            else:
                px[x, y] = LAND if is_land(lat, lon) else OCEAN

    # Sky strictly outside the disk — never slices into the globe
    for y in range(max(0, int(apex))):
        for x in range(s):
            dx = x - cx
            dy = y - cy
            if dx * dx + dy * dy > r2:
                px[x, y] = PAPER

    draw = ImageDraw.Draw(img)
    rim = []
    for i in range(500):
        t = i / 499
        ang = math.pi * (1 - t)
        x = cx + radius * math.cos(ang)
        y = cy - radius * math.sin(ang)
        rim.append((x + random.uniform(-1.0, 1.0) * scale, y + random.uniform(-0.8, 0.8) * scale))
    draw.line(rim, fill=INK, width=4 * scale, joint="curve")

    return img


def main() -> None:
    random.seed(3)
    img = render(SCALE).resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    img.save(OUT, format="PNG", optimize=True)
    img.save(PREVIEW, format="PNG", optimize=True)
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()