#!/usr/bin/env python3
"""Process generated art into game assets.

Backgrounds: any image in art/raw/ named bg-<scene>-*.webp/png -> art/bg-<scene>.png
  (960x540, RGB, centre-cropped to 16:9, LANCZOS).
NPCs: art/raw/ named npc-<id>-*.webp/png -> art/npc-<id>.png (RGBA as generated,
  transparent background verified; falls back to a report if opaque).

Usage: python3 scripts/process_art.py [--check-only]
"""
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "art" / "raw"
ART = ROOT / "art"


def process_bg(src: Path, scene: str, check_only: bool) -> str:
    im = Image.open(src).convert("RGB")
    w, h = im.size
    target_ratio = 16 / 9
    ratio = w / h
    if ratio > target_ratio:  # too wide: crop sides
        nw = int(h * target_ratio)
        x0 = (w - nw) // 2
        im = im.crop((x0, 0, x0 + nw, h))
    else:  # too tall: crop top/bottom (keep the floor!)
        nh = int(w / target_ratio)
        y0 = h - nh  # keep the bottom (floor)
        im = im.crop((0, y0, w, y0 + nh))
    im = im.resize((960, 540), Image.LANCZOS)
    out = ART / f"bg-{scene}.png"
    if not check_only:
        im.save(out, "PNG", optimize=True)
    return f"{scene}: {src.name} {im.size} -> {out.name} ({out.stat().st_size // 1024 if out.exists() else 0} KB)"


def process_npc(src: Path, npc: str, check_only: bool) -> str:
    """NPC sprites arrive on a near-white background (RGB). Remove the
    background by connected component (the white region touching the border)
    and feather the silhouette edge by 2 px. Downscale to height 900."""
    import numpy as np
    from scipy import ndimage

    im = Image.open(src).convert("RGB")
    w, h = im.size
    if h > 900:
        nw = int(w * 900 / h)
        im = im.resize((nw, 900), Image.LANCZOS)
    arr = np.array(im).astype(np.int16)
    near_white = arr.min(axis=2) > 235
    labelled, n = ndimage.label(near_white)
    border_labels = set()
    border_labels.update(np.unique(labelled[0, :]))
    border_labels.update(np.unique(labelled[-1, :]))
    border_labels.update(np.unique(labelled[:, 0]))
    border_labels.update(np.unique(labelled[:, -1]))
    border_labels.discard(0)
    background = np.isin(labelled, list(border_labels))
    foreground = ~background
    # Feather: alpha ramps over 2 px from the silhouette edge.
    dist = ndimage.distance_transform_edt(foreground)
    alpha = np.clip(dist * 127.5, 0, 255).astype(np.uint8)
    rgba = np.dstack([np.array(im), alpha])
    out_im = Image.fromarray(rgba, "RGBA")
    out = ART / f"npc-{npc}.png"
    if not check_only:
        out_im.save(out, "PNG", optimize=True)
    frac = float((alpha < 10).mean())
    return (f"{npc}: {src.name} {im.size} RGBA bg-removed "
            f"(transparent frac {frac:.2f}) -> {out.name} "
            f"({out.stat().st_size // 1024 if out.exists() else 0} KB)")


def main():
    check_only = "--check-only" in sys.argv
    for src in sorted(RAW.glob("*.webp")) + sorted(RAW.glob("*.png")):
        name = src.stem
        # generated names: media-generation-bg-workshop-0-<uuid>
        if name.startswith("media-generation-"):
            name = name[len("media-generation-"):]
        if name.startswith("bg-"):
            scene = name.split("-")[1]
            print(process_bg(src, scene, check_only))
        elif name.startswith("npc-"):
            # npc-mill-owner-0-<uuid> -> id "mill_owner"
            rest = name[4:]
            idx = rest.rfind("-0-")
            npc = rest[:idx].replace("-", "_") if idx > 0 else rest.split("-")[0]
            print(process_npc(src, npc, check_only))
        else:
            print(f"skip: {src.name}")


if __name__ == "__main__":
    main()
