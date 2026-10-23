#!/usr/bin/env python3
"""Build a styled NewChirp macOS DMG with a drag-to-Applications window."""

from __future__ import annotations

import argparse
import json
import shutil
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

import dmgbuild


def project_version() -> str:
    root = Path(__file__).resolve().parent.parent
    text = (root / 'pubspec.yaml').read_text(encoding='utf-8')
    version = text.split('version:', 1)[1].splitlines()[0].strip()
    return version.split('+', 1)[0]


def build_background(destination: Path) -> None:
    width, height = 660, 380
    top = (15, 23, 42)
    bottom = (30, 58, 138)

    image = Image.new("RGBA", (width, height))
    pixels = image.load()
    for y in range(height):
        t = y / max(height - 1, 1)
        color = tuple(
            round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)
        )
        for x in range(width):
            pixels[x, y] = (*color, 255)

    overlay = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    glow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse((110, 30, 550, 350), fill=(255, 255, 255, 22))
    glow = glow.filter(ImageFilter.GaussianBlur(48))
    image = Image.alpha_composite(image, glow)

    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((28, 22, width - 28, height - 22), radius=28,
                           outline=(255, 255, 255, 55), width=2)

    arrow_start = (245, 178)
    arrow_end = (398, 178)
    draw.line([arrow_start, arrow_end], fill=(255, 255, 255, 190), width=8)
    draw.polygon(
        [(arrow_end[0] - 12, arrow_end[1] - 18),
         (arrow_end[0] + 16, arrow_end[1]),
         (arrow_end[0] - 12, arrow_end[1] + 18)],
        fill=(255, 255, 255, 210),
    )

    try:
        font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 28)
    except OSError:
        font = ImageFont.load_default()

    label = "Drag NewChirp into Applications"
    box = draw.textbbox((0, 0), label, font=font)
    label_width = box[2] - box[0]
    draw.text(
        ((width - label_width) / 2, 284),
        label,
        font=font,
        fill=(255, 255, 255, 235),
    )

    image.convert("RGB").save(destination, "PNG")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", required=True, help="Path to NewChirp.app")
    parser.add_argument(
        "--output",
        default=None,
        help="Output DMG path",
    )
    parser.add_argument(
        "--volume-name",
        default="NewChirp",
        help="Mounted volume title",
    )
    args = parser.parse_args()

    app_path = Path(args.app).resolve()
    if not app_path.is_dir():
        raise SystemExit(f"App not found: {app_path}")

    output_path = Path(
        args.output or f"build/NewChirp-{project_version()}.dmg"
    ).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    staging_dir = Path(tempfile.mkdtemp(prefix="newchirp-dmg-"))
    try:
        background_path = staging_dir / "background.png"
        build_background(background_path)

        settings_path = staging_dir / "dmg_settings.json"
        settings = {
            "title": args.volume_name,
            "format": "UDZO",
            "filesystem": "HFS+",
            "background": str(background_path),
            "icon-size": 128,
            "window": {
                "position": {"x": 100, "y": 100},
                "size": {"width": 660, "height": 380},
            },
            "contents": [
                {
                    "x": 148,
                    "y": 112,
                    "type": "file",
                    "path": str(app_path),
                    "name": "NewChirp.app",
                },
                {
                    "x": 430,
                    "y": 112,
                    "type": "link",
                    "path": "/Applications",
                    "name": "Applications",
                },
            ],
        }
        settings_path.write_text(json.dumps(settings), encoding="utf-8")

        dmgbuild.build_dmg(
            str(output_path),
            args.volume_name,
            settings_file=str(settings_path),
        )
    finally:
        shutil.rmtree(staging_dir, ignore_errors=True)

    print(f"Created DMG: {output_path}")


if __name__ == "__main__":
    main()
