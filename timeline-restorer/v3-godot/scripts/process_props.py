#!/usr/bin/env python3
"""v3.2 art processing: slice the generated prop/icon grid sheets into
individual background-removed prop sprites.

Background removal rule (differs from process_walk on purpose): a pixel is
FOREGROUND unless it is near-white AND connected to the sheet border. That
keeps enclosed pale areas that are part of an object (paper sheets, a white
feather, a plastic bottle) while removing the white page around objects.
Objects are then grouped per grid cell by component centroid.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / 'art' / 'raw'
PROPS_OUT = ROOT / 'art' / 'props'
ICONS_OUT = ROOT / 'art' / 'icons'

MIN_COMPONENT_PX = 150


def find_raw(stem_part):
    hits = sorted(RAW.glob(f'*{stem_part}*'))
    if not hits:
        raise FileNotFoundError(stem_part)
    return hits[0]


def extract_cells(img, cells, cols=3, rows=3, max_dim=480):
    """cells: {(row, col): name} or {(row, col): (name, (r0, r1))} for spans.
    Returns {name: RGBA Image}."""
    rgb = np.asarray(img.convert('RGB')).astype(np.int32)
    h, w = rgb.shape[:2]
    near_white = rgb.min(axis=2) > 235
    lab, n = ndimage.label(near_white)
    border_ids = set(np.unique(np.concatenate([
        lab[0, :], lab[-1, :], lab[:, 0], lab[:, -1]])))
    border_ids.discard(0)
    background = np.isin(lab, list(border_ids))
    fg = ~background
    # Feather: alpha ramps over ~2 px inside the foreground.
    dist = ndimage.distance_transform_edt(fg)
    alpha = np.where(fg, np.clip(dist / 2.0, 0, 1) * 255, 0).astype(np.uint8)
    # Components of the hard foreground for grouping.
    hard = dist >= 1.0
    clab, cn = ndimage.label(hard)
    objs = ndimage.find_objects(clab)
    comps = []  # (cy, cx, pixels, slice, label_id)
    for i, sl in enumerate(objs, start=1):
        if sl is None:
            continue
        px = int((clab[sl] == i).sum())
        if px < MIN_COMPONENT_PX:
            continue
        cy = (sl[0].start + sl[0].stop) / 2.0
        cx = (sl[1].start + sl[1].stop) / 2.0
        comps.append((cy, cx, px, sl, i))
    out = {}
    for (r, c), spec in cells.items():
        if isinstance(spec, tuple):
            name, (rr0, rr1) = spec
        else:
            name, rr0, rr1 = spec, r, r
        y0, y1 = rr0 * h / rows, (rr1 + 1) * h / rows
        x0, x1 = c * w / cols, (c + 1) * w / cols
        mine = [cp for cp in comps if y0 <= cp[0] < y1 and x0 <= cp[1] < x1]
        if not mine:
            print(f'  !! no component found for {name} (r{r} c{c})')
            continue
        by0 = min(cp[3][0].start for cp in mine)
        by1 = max(cp[3][0].stop for cp in mine)
        bx0 = min(cp[3][1].start for cp in mine)
        bx1 = max(cp[3][1].stop for cp in mine)
        pad = 4
        by0 = max(0, by0 - pad); bx0 = max(0, bx0 - pad)
        by1 = min(h, by1 + pad); bx1 = min(w, bx1 + pad)
        # Mask: only this cell's components (plus feathered alpha inside bbox).
        keep = np.zeros((h, w), dtype=bool)
        for _, _, _, sl, cid in mine:
            keep[sl] |= clab[sl] == cid
        rgba = np.dstack([rgb.astype(np.uint8), alpha])
        crop_a = np.where(keep[by0:by1, bx0:bx1], alpha[by0:by1, bx0:bx1], 0)
        crop = np.dstack([rgba[by0:by1, bx0:bx1, :3], crop_a])
        pim = Image.fromarray(crop, 'RGBA')
        if max(pim.size) > max_dim:
            s = max_dim / max(pim.size)
            pim = pim.resize((round(pim.size[0] * s), round(pim.size[1] * s)),
                             Image.LANCZOS)
        out[name] = pim
    return out


SHEETS = {
    'props-a': {
        (0, 0): 'music_player', (0, 1): 'workbench', (0, 2): 'magnifier',
        (1, 0): 'leyden_jar', (1, 1): 'notes_stack', (1, 2): 'printing_press',
        (2, 0): 'copper_spool', (2, 1): 'ink_pot', (2, 2): 'colonial_coat',
    },
    'props-b': {
        (0, 0): 'lodestone', (0, 1): 'plastic_bottle', (0, 2): 'glass_tube',
        (1, 0): 'electric_lamp', (1, 1): 'books_row', (1, 2): 'timeline_chart',
        (2, 0): 'notice_board', (2, 1): 'candles', (2, 2): 'kite_sketch',
    },
    'props-c': {
        (0, 0): 'document_box', (0, 1): 'sealing_wax', (0, 2): 'compass',
        (1, 0): 'globe', (1, 1): 'radio', (1, 2): 'wrench',
        (2, 0): 'power_loom', (2, 1): 'work_chart',
    },
    'props-d': {
        (0, 0): 'accounts_papers', (0, 1): 'oil_can', (0, 2): 'cotton_bale',
        (1, 0): 'loom_shuttle', (1, 1): 'ledger', (1, 2): 'telescope',
        (2, 0): 'star_chart',
    },
    'props-e': {
        (0, 0): 'germ_chart', (0, 1): 'microscope', (0, 2): 'sealed_letter',
        (1, 0): 'manuscript', (1, 1): 'quill', (1, 2): 'principia',
        (2, 0): 'slate',
    },
    'props-f': {
        (0, 0): 'biplane', (0, 1): 'flight_log', (0, 2): 'spark_plug',
        (1, 0): 'assembly_notes', (1, 1): 'turbine_blade',
        (1, 2): ('fabric_roll', (1, 2)),
        (2, 0): 'parts_bench',
    },
    'props-g': {
        (0, 0): 'blueprint', (0, 1): 'rivet_box', (0, 2): 'propeller_blade',
        (1, 0): 'fracture', (1, 1): 'stream', (1, 2): 'memory_franklin',
        (2, 0): 'memory_mill', (2, 1): 'sigil', (2, 2): 'final_seal',
    },
}

ICON_CELLS = {
    (0, 0): 'look', (0, 1): 'talk', (0, 2): 'truth',
    (1, 0): 'use', (1, 1): 'interact', (1, 2): 'close',
}


def main():
    PROPS_OUT.mkdir(exist_ok=True)
    ICONS_OUT.mkdir(exist_ok=True)
    total = 0
    for stem, cells in SHEETS.items():
        path = find_raw(stem)
        img = Image.open(path)
        print(f'{stem}: {path.name} {img.size}')
        out = extract_cells(img, cells)
        for name, pim in out.items():
            dest = PROPS_OUT / f'prop-{name}.png'
            pim.save(dest)
            total += 1
            print(f'  -> {dest.name} {pim.size}')
    ipath = find_raw('verb-icons')
    iimg = Image.open(ipath)
    print(f'icons: {ipath.name} {iimg.size}')
    iout = extract_cells(iimg, ICON_CELLS, cols=3, rows=2, max_dim=200)
    for name, pim in iout.items():
        dest = ICONS_OUT / f'icon-{name}.png'
        pim.save(dest)
        total += 1
        print(f'  -> {dest.name} {pim.size}')
    print(f'TOTAL extracted: {total}')


if __name__ == '__main__':
    main()
