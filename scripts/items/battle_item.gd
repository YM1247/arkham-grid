class_name BattleItem extends Resource

const CATEGORY_ORDER := ["single_attack", "spread_attack", "all_attack", "defense", "empower", "poison", "weaken"]

@export_group("基本資料")
@export var content_id: String = ""
@export var spell_name: String = "未命名咒文"
@export var icon: Texture2D
@export var icon_text: String = "✦"
@export var category_id: String = "single_attack"
@export var category_name: String = "單體攻擊"
@export var category_glyph: String = "✦"
@export var category_color: Color = Color("ff9b54")
@export var logic: String = ""
@export var rarity: String = "common"
@export var tier: int = 1
@export var balance_cost: int = 0
@export var upgrade_from: String = ""
@export var upgrade_to: String = ""
@export var combine_count: int = 0
@export var tags: Array[String] = []
@export var mp_cost: int = 0
@export var effect_scope: String = "single"
@export var status_effects_self: Array[Dictionary] = []
@export var status_effects_target: Array[Dictionary] = []
@export_multiline var description: String

func get_effect_tooltip(header: String = "") -> String:
	var lines: Array[String] = []
	if header != "":
		lines.append(header)
	lines.append(spell_name)
	lines.append("%s咒文｜Tier %d｜MP %d" % [_get_rarity_name(rarity), tier, mp_cost])
	lines.append("MP 不足時改以同額 Sanity 支付")
	if description != "":
		lines.append(description)
	lines.append("範圍：%s" % _get_effect_scope_name(effect_scope))
	if logic == "attack" or logic == "conditional_attack":
		lines.append("傷害：%d x %d" % [_get_int_property("damage", 0), _get_int_property("hit_count", 1)])
		var bonus_damage = _get_int_property("bonus_damage", 0)
		if bonus_damage > 0:
			lines.append("條件傷害：%d" % bonus_damage)
	if logic == "support":
		var armor_gain = _get_int_property("armor_gain", 0)
		var heal_amount = _get_int_property("heal_amount", 0)
		if armor_gain > 0:
			lines.append("護甲：+%d" % armor_gain)
		if heal_amount > 0:
			lines.append("治療：+%d" % heal_amount)
	for effect in status_effects_self:
		lines.append("自身：%s%d" % [_get_status_display_name(str(effect.get("id", ""))), int(effect.get("amount", 0))])
	for effect in status_effects_target:
		lines.append("目標：%s%d" % [_get_status_display_name(str(effect.get("id", ""))), int(effect.get("amount", 0))])
	return "\n".join(lines)


func get_icon_color() -> Color:
	if category_color.a > 0.0:
		return category_color
	if "ailment" in tags:
		return Color(0.82, 0.48, 1.0)
	if "ward" in tags:
		return Color(0.4, 0.85, 1.0)
	if "risk" in tags:
		return Color(1.0, 0.45, 0.55)
	if logic == "attack" or logic == "conditional_attack":
		return Color(1.0, 0.68, 0.3)
	return Color(0.95, 0.9, 0.35)


func get_category_label() -> String:
	return category_name if not category_name.is_empty() else category_id


func get_short_summary() -> String:
	return description if description.length() <= 28 else description.left(27) + "…"

func _get_rarity_name(value: String) -> String:
	match value:
		"uncommon": return "非凡"
		"rare": return "稀有"
		_: return "普通"

func _get_effect_scope_name(scope: String) -> String:
	match scope:
		"single":
			return "單體"
		"spread":
			return "擴散"
		"all":
			return "全體"
		"self":
			return "自身"
		_:
			return scope

func _get_status_display_name(status_id: String) -> String:
	match status_id:
		"strength":
			return "力量"
		"weak":
			return "虛弱"
		"hard":
			return "堅硬"
		"fragile":
			return "脆弱"
		"regen":
			return "再生"
		"poison":
			return "中毒"
		_:
			return status_id

func _get_int_property(property_name: String, default_value: int = 0) -> int:
	var value = get(property_name)
	if value == null:
		return default_value
	return int(value)

# --- 虛擬函數 (讓子類別覆寫) ---
# target = 敵人節點, user = 玩家節點
func execute(target: Node, user: Node):
	pass


func execute_with_context(target: Node, user: Node, _context: BattleEffectContext = null) -> void:
	execute(target, user)
