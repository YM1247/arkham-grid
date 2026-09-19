class_name CombatIconRegistry
extends RefCounted

const STATUS := {
	"strength": {"glyph": "▲", "label": "力量", "color": Color("f1b968")},
	"weak": {"glyph": "▼", "label": "虛弱", "color": Color("c98de8")},
	"hard": {"glyph": "⬢", "label": "堅硬", "color": Color("79c5e8")},
	"fragile": {"glyph": "◇", "label": "脆弱", "color": Color("e99383")},
	"poison": {"glyph": "☣", "label": "中毒", "color": Color("8dc276")},
	"regen": {"glyph": "✚", "label": "再生", "color": Color("82d6a0")},
}

const INTENTS := {
	"attack": {"glyph": "↘", "label": "攻擊"},
	"heavy_attack": {"glyph": "✹", "label": "重擊"},
	"guard": {"glyph": "⬢", "label": "防禦"},
	"sanity_attack": {"glyph": "◉", "label": "精神侵蝕"},
	"debuff_player": {"glyph": "◆", "label": "詛咒"},
	"buff_self": {"glyph": "▲", "label": "蓄勢"},
	"watch": {"glyph": "◌", "label": "窺視"},
	"brace": {"glyph": "⬟", "label": "凝神防備"},
}

static func status_glyph(status_id: String) -> String:
	return str(STATUS.get(status_id, {}).get("glyph", "•"))

static func status_label(status_id: String) -> String:
	return str(STATUS.get(status_id, {}).get("label", status_id))

static func status_color(status_id: String) -> Color:
	return STATUS.get(status_id, {}).get("color", Color.WHITE) as Color

static func intent_glyph(intent_id: String) -> String:
	return str(INTENTS.get(intent_id, {}).get("glyph", "?"))

static func intent_label(intent_id: String) -> String:
	return str(INTENTS.get(intent_id, {}).get("label", intent_id))

static func status_summary(entity: Entity) -> String:
	if entity == null:
		return ""
	var parts: Array[String] = []
	for status_id in entity.statuses.keys():
		var amount := entity.get_status_amount(str(status_id))
		if amount > 0:
			parts.append("%s%d" % [status_glyph(str(status_id)), amount])
	return " ".join(parts)
