#!/usr/bin/env python3
"""v3.2 data edits to data/game_data.json:
1. Add `prop` (sprite key) + `propW` (display width px) to every non-NPC
   hotspot so the game can draw a visible painted prop instead of a ring.
2. Add the OPTIONAL Colonial Coat item + its workshop hotspot.
3. Add Franklin's one-off coat acknowledgement dialogue node.
All text is original to this project. Idempotent: safe to re-run.
"""
import json
from pathlib import Path

DATA = Path(__file__).resolve().parent.parent / 'data' / 'game_data.json'

# hotspot_id -> (prop key, display width px)
PROPS = {
    # workshop
    'music_player': ('music_player', 100), 'bench_puzzle': ('workbench', 250),
    'magnifier_ws': ('magnifier', 95), 'leyden_jar': ('leyden_jar', 100),
    'workbench_notes': ('notes_stack', 120),
    # printshop
    'press': ('printing_press', 250), 'copper_wire': ('copper_spool', 95),
    'ink_pot': ('ink_pot', 85),
    # marketplace
    'lodestone_stall': ('lodestone', 95), 'plastic_bottle': ('plastic_bottle', 70),
    # library
    'glass_tube': ('glass_tube', 75), 'electric_lamp': ('electric_lamp', 100),
    'shelf_books': ('books_row', 190), 'franklin_timeline': ('timeline_chart', 200),
    # street
    'notice_board': ('notice_board', 200), 'candle_stall': ('candles', 90),
    'kite_sketch': ('kite_sketch', 110),
    # meeting
    'document_box': ('document_box', 150), 'sealing_wax': ('sealing_wax', 130),
    'compass': ('compass', 110), 'globe': ('globe', 120),
    # mill
    'radio_set': ('radio', 140), 'wrench_mill': ('wrench', 130),
    'power_loom': ('power_loom', 265), 'loom_sequence': ('work_chart', 140),
    # cottage
    'three_stories': ('accounts_papers', 150), 'oil_can': ('oil_can', 110),
    'cotton_bale': ('cotton_bale', 170),
    # warehouse
    'loom_shuttle': ('loom_shuttle', 150), 'ledger_book': ('ledger', 140),
    'wire_warehouse': ('copper_spool', 95),
    # observatory
    'telescope': ('telescope', 190), 'star_chart': ('star_chart', 150),
    'wax_observatory': ('sealing_wax', 130),
    # apothecary
    'germ_chart': ('germ_chart', 200), 'ink_pot_apoth': ('ink_pot', 85),
    'microscope': ('microscope', 110), 'traveller_note': ('sealed_letter', 130),
    # university
    'manuscript': ('manuscript', 110), 'quill': ('quill', 70),
    'principia': ('principia', 140), 'scholar_slate': ('slate', 170),
    # airfield
    'biplane': ('biplane', 300), 'flight_log': ('flight_log', 110),
    'spark_plug': ('spark_plug', 70), 'assembly_notes': ('assembly_notes', 150),
    # hangar
    'turbine_blade': ('turbine_blade', 170), 'wrench_hangar': ('wrench', 130),
    'fabric_roll': ('fabric_roll', 80), 'parts_bench': ('parts_bench', 240),
    # office
    'blueprint': ('blueprint', 200), 'rivet_box': ('rivet_box', 140),
    'propeller_blade': ('propeller_blade', 55),
    # core
    'core_fracture': ('fracture', 170), 'timeline_stream1': ('stream', 190),
    # gallery
    'memory_franklin': ('memory_franklin', 150), 'memory_mill': ('memory_mill', 150),
    'chronarch_sigil': ('sigil', 120),
    # dais
    'final_seal': ('final_seal', 190),
    # v3.2 coat
    'coat_stand': ('colonial_coat', 100),
}

COAT_ITEM = {
    'id': 'colonial_coat',
    'name': 'Colonial Coat',
    'desc': 'A fine burgundy frock coat with brass buttons, hanging in '
            "Franklin's workshop. Wearing it is pure style — and entirely "
            'optional. Use it from your pack to put it on or take it off.',
    'icon': '\U0001F9E5',
    'era': '1764',
    'category': 'wardrobe',
    'usableWith': [],
    'combineWith': [],
    'paradoxValue': 0,
}

COAT_HOTSPOT = {
    'id': 'coat_stand',
    'name': 'Colonial Coat',
    'icon': '\U0001F9E5',
    'x': 9,
    'y': 44,
    'desc': 'A handsome burgundy frock coat hangs on a stand by the door, '
            'its brass buttons polished bright. It looks about your size... '
            'Franklin would not mind a young friend borrowing a little '
            'Philadelphia style, surely.',
    'actions': ['look', 'interact'],
    'item': 'colonial_coat',
    'prop': 'colonial_coat',
    'propW': 100,
}

COAT_LINE_NODE = {
    'text': 'Franklin sets down his pen and beams. “Well, well! With my '
            'old coat upon your shoulders, you look a proper young '
            'Philadelphian, fit for any parlour in the city. It suits '
            'you, Cadet.”',
    'choices': [
        {
            'text': '“Thank you, Mr. Franklin!”',
            'response': '“Ha! Wear it in good health. Only mind you '
                        'return it before you hop home — Deborah keeps a '
                        'careful tally of my wardrobe.”',
            'next': 'n1',
        },
    ],
}


def main():
    D = json.loads(DATA.read_text(encoding='utf-8'))
    changed = 0
    for scene_id, scene in D['scenes'].items():
        for hs in scene['hotspots']:
            if 'npc' in hs:
                continue
            spec = PROPS.get(hs['id'])
            if spec is None:
                if hs['id'] != 'coat_stand':
                    print(f'  !! no prop mapping for hotspot {hs["id"]} '
                          f'in {scene_id}')
                continue
            hs['prop'], hs['propW'] = spec
            changed += 1
    print(f'props assigned: {changed}')
    ws = D['scenes']['workshop']['hotspots']
    if not any(h['id'] == 'coat_stand' for h in ws):
        ws.append(COAT_HOTSPOT)
        print('coat_stand hotspot added to workshop')
    D['items']['colonial_coat'] = COAT_ITEM
    nodes = D['dialogues']['franklin_intro']['nodes']
    nodes['coat_line'] = COAT_LINE_NODE
    DATA.write_text(json.dumps(D, indent=1, ensure_ascii=False) + '\n',
                    encoding='utf-8')
    print('game_data.json updated')


if __name__ == '__main__':
    main()
