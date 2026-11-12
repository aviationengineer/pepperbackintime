#!/usr/bin/env python3
"""Slice the generated Cadet walk-cycle sheet into a uniform sprite strip.

Input : art/raw/media-generation-cadet-walk-sheet-*.png  (8 side-profile
        frames of the same character on a solid white background)
Output: art/cadet-walk.png — a horizontal strip of N equal cells
        (FRAME_W x 900), transparent background, feet on a common baseline,
        all frames scaled by ONE factor (proportions preserved).

The background is removed exactly like process_art.py does for the NPCs
(connected near-white region touching the border + 2 px feather).
Frames are found as runs of foreground columns separated by empty gaps.

Usage: python3 scripts/process_walk.py
"""
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "art" / "raw"
OUT = ROOT / "art" / "cadet-walk.png"
TARGET_H = 900
PAD = 6  # horizontal padding inside each cell


def remove_background(im: Image.Image):
    """Sheet-specific background removal. The plain border-connected rule
    (process_art.py) fails here: the wide stride poses enclose big white
    pockets between the legs that are NOT connected to the border, and
    would render as white wedges. Rule: a near-white region counts as
    character detail (watch face, eye whites, highlights) only when it is
    small (< 4000 px); border-connected and large enclosed near-white
    regions are background. Alpha then feathers over 2 px from the true
    silhouette via a distance transform of that foreground."""
    arr = np.array(im.convert("RGB")).astype(np.int16)
    near_white = arr.min(axis=2) > 235
    labelled, _ = ndimage.label(near_white)
    border = set()
    border.update(np.unique(labelled[0, :]))
    border.update(np.unique(labelled[-1, :]))
    border.update(np.unique(labelled[:, 0]))
    border.update(np.unique(labelled[:, -1]))
    border.discard(0)
    sizes = ndimage.sum(near_white, labelled,
                        range(1, labelled.max() + 1)) if labelled.max() else []
    background_labels = set(border)
    for lbl in range(1, labelled.max() + 1):
        if lbl not in border and sizes[lbl - 1] >= 4000:
            background_labels.add(lbl)
    background = np.isin(labelled, list(background_labels))
    foreground = ~background
    dist = ndimage.distance_transform_edt(foreground)
    alpha = np.clip(dist * 127.5, 0, 255).astype(np.uint8)
    rgba = np.dstack([np.array(im.convert("RGB")), alpha])
    return Image.fromarray(rgba, "RGBA"), alpha


def column_runs(alpha: np.ndarray):
    col_has = (alpha > 30).any(axis=0)
    runs = []
    start = None
    for x, has in enumerate(col_has):
        if has and start is None:
            start = x
        elif not has and start is not None:
            runs.append((start, x))
            start = None
    if start is not None:
        runs.append((start, len(col_has)))
    # Merge runs separated by tiny gaps (stray marks / chain links).
    merged = []
    for r in runs:
        if merged and r[0] - merged[-1][1] <= 6:
            merged[-1] = (merged[-1][0], r[1])
        else:
            merged.append(list(r))
    # Drop slivers (noise specks) narrower than 3% of the median width.
    widths = sorted(b - a for a, b in merged)
    if widths:
        med = widths[len(widths) // 2]
        merged = [r for r in merged if r[1] - r[0] >= 0.25 * med]
    return [tuple(r) for r in merged]


def slice_frames(rgba: Image.Image, alpha: np.ndarray):
    """Split the sheet into its 8 figures. Adjacent figures overlap in
    column projection (stride poses are wider than the pitch) and touch in
    a few pixels, so: cut at the column-count valleys between figures,
    then keep only the largest connected component inside each slice —
    severed boot-tips and stray marks from the neighbours are discarded."""
    from scipy import ndimage as _ndi

    counts = (alpha > 30).sum(axis=0)
    w = rgba.width
    pitch = w / 8.0
    bounds = [0]
    for i in range(1, 8):
        cx = int(pitch * i)
        lo, hi = max(0, cx - 90), min(w, cx + 90)
        bounds.append(lo + int(np.argmin(counts[lo:hi])))
    bounds.append(w)
    frames = []
    for i in range(8):
        x0, x1 = bounds[i], bounds[i + 1]
        crop = np.array(rgba.crop((x0, 0, x1, rgba.height)))
        mask = crop[:, :, 3] > 30
        # Erode before labelling so thin bridges between figures break;
        # give every original mask pixel to its NEAREST eroded component
        # and keep the largest component's pixels. Then rescue dropped
        # components that sit fully inside the figure (a pocket watch
        # whose chain eroded away) — but never rescue fragments touching
        # the slice's left/right edge: those are the neighbours' limbs.
        eroded = _ndi.binary_erosion(mask, iterations=3)
        lab, n = _ndi.label(eroded)
        if n > 1:
            sizes = _ndi.sum(eroded, lab, range(1, n + 1))
            keep = int(np.argmax(sizes)) + 1
            _, inds = _ndi.distance_transform_edt(lab == 0,
                                                  return_indices=True)
            nearest = lab[tuple(inds)]
            kept = mask & (nearest == keep)
            dropped = mask & ~kept
            dlab, dn = _ndi.label(dropped)
            h, wdt = mask.shape
            ys, xs = np.where(kept)
            fy0, fy1, fx0, fx1 = ys.min(), ys.max(), xs.min(), xs.max()
            for d in range(1, dn + 1):
                comp = dlab == d
                cys, cxs = np.where(comp)
                touches_edge = cxs.min() <= 0 or cxs.max() >= wdt - 1
                interior = (cys.min() >= fy0 and cys.max() <= fy1
                            and cxs.min() >= fx0 and cxs.max() <= fx1)
                if interior and not touches_edge:
                    kept |= comp
            crop[:, :, 3] = np.where(kept, crop[:, :, 3], 0)
        ys, xs = np.where(crop[:, :, 3] > 30)
        frame = Image.fromarray(crop, "RGBA").crop(
            (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
        frames.append(frame)
    return frames, bounds


def main():
    srcs = sorted(RAW.glob("media-generation-cadet-walk-sheet-*.png"))
    assert srcs, "walk sheet not found in art/raw/"
    src = srcs[-1]
    im = Image.open(src)
    print(f"source: {src.name} {im.size}")
    rgba, alpha = remove_background(im)
    frames, bounds = slice_frames(rgba, alpha)
    print(f"sliced {len(frames)} frames at bounds {bounds}")
    print("frame sizes:", [f.size for f in frames])
    # One shared scale factor: tallest frame becomes TARGET_H tall.
    scale = TARGET_H / max(f.height for f in frames)
    frames = [f.resize((round(f.width * scale), round(f.height * scale)),
                       Image.LANCZOS) for f in frames]
    cell_w = max(f.width for f in frames) + PAD * 2
    strip = Image.new("RGBA", (cell_w * len(frames), TARGET_H), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        x = i * cell_w + (cell_w - f.width) // 2
        y = TARGET_H - f.height  # feet on the common baseline
        strip.paste(f, (x, y), f)
    strip.save(OUT, "PNG", optimize=True)
    print(f"wrote {OUT.name}: {strip.size} cell={cell_w}x{TARGET_H} "
          f"frames={len(frames)} scale={scale:.3f}")


def clean_strip():
    """Final pass on the assembled strip: in each cell, drop alpha
    components that are tiny (< 2% of the cell's main figure) and sit in
    the cell's outer 15% side bands — the last slivers of neighbouring
    figures that were painted overlapping the hero figure itself."""
    from scipy import ndimage as _ndi

    strip = Image.open(OUT)
    arr = np.array(strip)
    cell_w = strip.width // 8
    # Hand-verified corner cuts for cell 5 of THIS sheet: the neighbours'
    # boot tips are painted into the hero figure's silhouette there (one
    # connected component, so the generic passes cannot remove them).
    # Rects are (x0, y0, x1, y1) in cell space; the hero spans x 44-402.
    for (cx0, cy0, cx1, cy1) in [(0, 780, 42, 900), (404, 650, cell_w, 900)]:
        arr[cy0:cy1, 5 * cell_w + cx0:5 * cell_w + cx1, 3] = 0
    for i in range(8):
        cell = arr[:, i * cell_w:(i + 1) * cell_w, 3]
        mask = cell > 30
        lab, n = _ndi.label(mask)
        if n <= 1:
            continue
        sizes = _ndi.sum(mask, lab, range(1, n + 1))
        main = sizes.max()
        for c in range(1, n + 1):
            if sizes[c - 1] >= 0.02 * main:
                continue
            ys, xs = np.where(lab == c)
            in_band = xs.min() < 0.15 * cell_w or xs.max() > 0.85 * cell_w
            if in_band:
                cell[lab == c] = 0
        arr[:, i * cell_w:(i + 1) * cell_w, 3] = cell
    Image.fromarray(arr, "RGBA").save(OUT, "PNG", optimize=True)
    print("strip cleaned")


if __name__ == "__main__":
    main()
    clean_strip()
