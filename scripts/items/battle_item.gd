class_name BattleItem extends Resource

# 定義四種裝備類型
enum ItemType {
	WEAPON,    # 武器 (橫列 1-4)
	EQUIPMENT, # 裝備 (橫列 5-8)
	PRAYER,    # 祈禱 (直行 1-4)
	CURSE      # 詛咒 (直行 5-8)
}

enum AxisType {
	PHYSICAL,
	MAGIC
}

@export_group("基本資料")
@export var content_id: String = ""
@export var item_name: String = "未命名道具"
@export var icon: Texture2D
@export var item_type: ItemType # 遷移相容欄位
@export var axis_type: AxisType = AxisType.PHYSICAL
@export var logic: String = ""
@export var rarity: String = "common"
@export var tier: int = 1
@export var balance_cost: int = 0
@export var upgrade_from: String = ""
@export var upgrade_to: String = ""
@export var combine_count: int = 0
@export var tags: Array[String] = []
@export var sanity_cost: int = 0
@export var effect_scope: String = "single"
@export var status_effects_self: Array[Dictionary] = []
@export var status_effects_target: Array[Dictionary] = []
@export_multiline var description: String

func get_effect_tooltip(header: String = "") -> String:
	var lines: Array[String] = []
	if header != "":
		lines.append(header)
	lines.append(item_name)
	lines.append("%s｜Tier %d｜成本 %d" % [_get_rarity_name(rarity), tier, balance_cost])
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
	if axis_type == AxisType.MAGIC:
		var cost = sanity_cost if sanity_cost > 0 else 3
		var adjusted_cost := int(get_meta("sanity_adjusted_cost", cost))
		lines.append("Sanity 消耗：%d%s" % [adjusted_cost, "（基礎 %d）" % cost if adjusted_cost != cost else ""])
		var preview := str(get_meta("sanity_preview", ""))
		if not preview.is_empty():
			lines.append(preview)
	return "\n".join(lines)

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
