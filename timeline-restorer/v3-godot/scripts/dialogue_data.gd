class_name DialogueData
extends RefCounted

## Ported verbatim from Timeline Restorer v1 (GAME_DATA: dialogues.franklin_intro,
## truths, items, puzzles). Act 1 workshop slice only — the PoC is one scene.

const FRANKLIN_INTRO := {
	"start": "n1",
	"nodes": {
		"n1": {
			"text": "Franklin looks up from the humming device. “You carry yourself like a person out of their century, friend. That box sings, and I cannot say how. Tell me — what do you make of it?”",
			"choices": [
				{
					"text": "“It is a scientific instrument. Best left alone.”",
					"response": "Franklin nods slowly. “A cautious answer. Caution is a virtue I have come to respect.” He sets the device down and steps back from it.",
					"effects": {"paradox": -2, "score": 20, "flag": "franklin_warned"},
					"next": "n2",
				},
				{
					"text": "“It is from the future. Two hundred years from now.”",
					"response": "Franklin's eyes widen — and then, dangerously, they gleam. “The future! Then tell me everything. What wonders come? What machines? What knowledge?” The device hums louder, as if pleased.",
					"effects": {"paradox": 8, "score": 0, "flag": "franklin_knows_future"},
					"next": "n3",
				},
				{
					"text": "“I found it in the marketplace.”",
					"response": "“The marketplace?” Franklin frowns. “Then someone in this city is selling tomorrow. That is a trade I would like to understand — and stop.”",
					"effects": {"paradox": 0, "score": 10, "flag": "franklin_suspects_market"},
					"next": "n2",
				},
				{
					"text": "[Truth Check] Examine Franklin first",
					"response": "You study him carefully. He is a man of his time — ink on his fingers, curiosity in his eyes. The distortion is the device, not the man.",
					"effects": {"paradox": 0, "score": 10, "truth": "franklin_man"},
					"next": "n1",
				},
			],
		},
		"n2": {
			"text": "“The device is not of this age, I am certain of that much,” Franklin says. “I have spent my life studying electricity, and this box holds lightning in a way I do not understand. If you can silence it without harming my workshop, I will help you however I can.”",
			"choices": [
				{
					"text": "“I need to build a resonator — wire, lodestone and glass.”",
					"response": "“Wire I have. Lodestone you will find in the market. Glass tubing, in the library's instrument cabinet. Build it, and I will hold the door against interruption.”",
					"effects": {"score": 30, "flag": "franklin_helping"},
					"next": "",
				},
				{
					"text": "“Tell me about your kite experiment.”",
					"response": "“Ah — the kite. In 1752 I showed that lightning is electricity. Some say I flew it in a storm alone; I did not. My son William stood with me, and we were careful. History will embroider the rest.”",
					"effects": {"score": 25, "truth": "kite_experiment"},
					"next": "",
				},
			],
		},
		"n3": {
			"text": "“The future!” Franklin laughs, delighted. “Do they fly? Do they speak across oceans without wires? Tell me one thing — only one — and I shall keep it safe.”",
			"choices": [
				{
					"text": "Refuse. “Some knowledge must wait for its own time.”",
					"response": "Franklin studies you for a long moment, then nods. “You are right, of course. A seed planted in winter rots. I shall forget what I have guessed.” The device dims slightly.",
					"effects": {"paradox": -5, "score": 40, "flag": "franklin_warned"},
					"next": "n2",
				},
				{
					"text": "Tell him about electric light.",
					"response": "“Light without flame!” Franklin breathes. “I shall think of nothing else for a month.” The distortion in the room deepens — the lamp in the library begins to glow of its own accord.",
					"effects": {"paradox": 10, "score": 0, "flag": "franklin_knows_light"},
					"next": "",
				},
			],
		},
	},
}

const TRUTHS := {
	"music_player": {
		"object": "Portable Music Player",
		"status": "anachronistic",
		"fact": "ALTERNATE TIMELINE: portable digital music players appeared in the late 20th century. In 1764 there were no batteries, no transistors, no recorded sound. This object is the anchor of the Act 1 anomaly.",
		"confidence": 99,
		"expectedEra": "Late 20th century",
		"currentEra": "1764",
		"paradox": 12,
		"clue": "It hums with stored lightning. It needs a counter-frequency to discharge safely — a resonator built from this century's materials.",
	},
	"leyden_jar": {
		"object": "Leyden Jar",
		"status": "authentic",
		"fact": "FACT: the Leyden jar — a glass jar lined with metal foil that stores static electricity — was invented in 1745–46. Franklin used it in his electrical experiments in the 1750s.",
		"confidence": 97,
		"expectedEra": "18th century",
		"currentEra": "1764",
		"paradox": 0,
		"clue": "Period materials, correctly used.",
	},
	"franklin_man": {
		"object": "Benjamin Franklin",
		"status": "authentic",
		"fact": "FACT: Benjamin Franklin (1706–1790) was a printer, scientist, inventor and statesman. In 1764 he was in Philadelphia, already famous for his electrical work.",
		"confidence": 99,
		"expectedEra": "18th century",
		"currentEra": "1764",
		"paradox": 0,
		"clue": "The man is real. The device has changed him — not the other way around.",
	},
	"kite_experiment": {
		"object": "The Kite Experiment",
		"status": "authentic",
		"fact": "FACT: in 1752 Franklin showed that lightning is electricity, flying a kite in a storm with his son William. He did not fly it alone, whatever the stories say.",
		"confidence": 96,
		"expectedEra": "18th century",
		"currentEra": "1752",
		"paradox": 0,
		"clue": "A true story, told by the man who lived it.",
	},
}

const HOTSPOTS := {
	"music_player": {
		"name": "Humming Device",
		"pos": Vector2(880, 560),
		"approach": Vector2(860, 665),
		"actions": ["look", "truth"],
		"desc": "A small black rectangle with a glowing screen. It plays music no instrument in 1764 could make. It is the anomaly — handle it with care.",
		"truth": "music_player",
	},
	"magnifier": {
		"name": "Magnifying Glass",
		"pos": Vector2(300, 640),
		"approach": Vector2(300, 690),
		"actions": ["look", "take"],
		"desc": "A brass magnifying glass, left beside a stack of letters.",
		"item": "magnifier",
	},
	"leyden_jar": {
		"name": "Leyden Jar",
		"pos": Vector2(430, 640),
		"approach": Vector2(430, 690),
		"actions": ["look", "truth"],
		"desc": "A glass jar lined with metal foil — Franklin's electrical storage jar. FACT: the Leyden jar was invented in 1745–46 and Franklin used it in his electrical experiments.",
		"truth": "leyden_jar",
	},
	"franklin": {
		"name": "Benjamin Franklin",
		"pos": Vector2(1090, 640),
		"approach": Vector2(1010, 660),
		"actions": ["look", "talk", "truth"],
		"desc": "Benjamin Franklin, printer and natural philosopher, frowning at the humming device.",
		"npc": "franklin",
		"truth": "franklin_man",
	},
	"notes": {
		"name": "Workbench Notes",
		"pos": Vector2(560, 600),
		"approach": Vector2(560, 690),
		"actions": ["look"],
		"desc": "Notes in Franklin's hand about electricity — and a sketch of the humming device, drawn as if he had seen it in a dream.",
	},
}
