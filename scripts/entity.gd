extends Node
class_name Entity

signal stats_changed(entity: Entity)
signal died(entity: Entity)
signal combat_feedback(entity: Entity, message: String, color: Color)
signal sanity_depleted(entity: Entity)
signal damage_resolved(entity: Entity, hp_damage: int, blocked_damage: int)
signal armor_gained(entity: Entity, amount: int)
signal sanity_spent(entity: Entity, amount: int)
signal sanity_changed(entity: Entity, delta: int, source: String, before: int, after: int)

@export var entity_name: String = "Entity"
@export var max_hp: int = 100
@export var hp: int = 100
@export var armor: int = 0
@export var max_sanity: int = 0
@export var sanity: int = 0

var is_dead: bool = false
var statuses: Dictionary = {}

func _ready() -> void:
	hp = clampi(hp, 0, max_hp)
	sanity = clampi(sanity, 0, max_sanity)
	stats_changed.emit(self)

func reset_entity(new_name: String, new_max_hp: int, new_hp: int = -1, new_max_sanity: int = -1, new_sanity: int = -1) -> void:
	entity_name = new_name
	max_hp = maxi(new_max_hp, 1)
	hp = max_hp if new_hp < 0 else clampi(new_hp, 0, max_hp)
	if new_max_sanity >= 0:
		max_sanity = new_max_sanity
	if new_sanity >= 0:
		sanity = clampi(new_sanity, 0, max_sanity)
	armor = 0
	statuses.clear()
	is_dead = false
	stats_changed.emit(self)

func take_damage(amount: int) -> int:
	if is_dead:
		return 0
	var incoming_damage = maxi(amount, 0)
	var blocked_damage = mini(armor, incoming_damage)
	armor -= blocked_damage
	var final_damage = incoming_damage - blocked_damage
	hp = maxi(hp - final_damage, 0)
	if not bool(get_meta("simulation_quiet", false)):
		print(entity_name, " 受到 ", final_damage, " 點傷害，護甲抵擋 ", blocked_damage, " 點。")
	if blocked_damage > 0:
		combat_feedback.emit(self, "護甲 -%d" % blocked_damage, Color(0.5, 0.85, 1.0))
	if final_damage > 0:
		combat_feedback.emit(self, "-%d HP" % final_damage, Color(1.0, 0.25, 0.25))
	damage_resolved.emit(self, final_damage, blocked_damage)
	stats_changed.emit(self)
	if hp <= 0:
		_die()
	return final_damage

func modify_attack_damage(amount: int) -> int:
	return maxi(amount + get_status_amount("strength") - get_status_amount("weak") + int(get_meta("madness_attack_modifier", 0)), 0)

func heal(amount: int) -> int:
	if is_dead:
		return 0
	var old_hp = hp
	hp = mini(hp + maxi(amount, 0), max_hp)
	var healed_amount = hp - old_hp
	if not bool(get_meta("simulation_quiet", false)):
		print(entity_name, " 回復 ", healed_amount, " 生命。")
	if healed_amount > 0:
		combat_feedback.emit(self, "+%d HP" % healed_amount, Color(0.35, 1.0, 0.45))
	stats_changed.emit(self)
	return healed_amount

func add_armor(amount: int) -> int:
	var gained_armor = maxi(amount, 0)
	armor += gained_armor
	if not bool(get_meta("simulation_quiet", false)):
		print(entity_name, " 獲得 ", gained_armor, " 護甲。")
	if gained_armor > 0:
		combat_feedback.emit(self, "+%d 護甲" % gained_armor, Color(0.45, 0.8, 1.0))
		armor_gained.emit(self, gained_armor)
	stats_changed.emit(self)
	return gained_armor

func modify_armor_gain(amount: int) -> int:
	return maxi(amount + get_status_amount("hard") - get_status_amount("fragile") + int(get_meta("madness_armor_modifier", 0)), 0)

func clear_armor() -> void:
	if armor <= 0:
		return
	armor = 0
	stats_changed.emit(self)

func clear_statuses() -> void:
	if statuses.is_empty():
		return
	statuses.clear()
	stats_changed.emit(self)

func spend_sanity(amount: int, source: String = "unknown") -> int:
	var sanity_cost = maxi(amount, 0)
	return -change_sanity(-sanity_cost, source)


func change_sanity(delta: int, source: String) -> int:
	if max_sanity <= 0 or delta == 0:
		return 0
	var before := sanity
	sanity = clampi(sanity + delta, 0, max_sanity)
	var applied_delta := sanity - before
	var spent_amount := maxi(-applied_delta, 0)
	if not bool(get_meta("simulation_quiet", false)):
		print(entity_name, " Sanity 變化 ", applied_delta, "（", source, "）。")
	if applied_delta < 0:
		combat_feedback.emit(self, "%d SAN" % applied_delta, Color(0.8, 0.45, 1.0))
	elif applied_delta > 0:
		combat_feedback.emit(self, "+%d SAN" % applied_delta, Color(0.45, 0.9, 1.0))
	if spent_amount > 0:
		sanity_spent.emit(self, spent_amount)
	if applied_delta != 0:
		sanity_changed.emit(self, applied_delta, source, before, sanity)
	stats_changed.emit(self)
	if max_sanity > 0 and sanity <= 0:
		sanity_depleted.emit(self)
	return applied_delta

func apply_status_effects(effects: Array) -> void:
	for effect in effects:
		if not effect is Dictionary:
			continue
		var status_id = str(effect.get("id", ""))
		var amount = int(effect.get("amount", 0))
		add_status(status_id, amount)

func add_status(status_id: String, amount: int) -> void:
	if status_id == "" or amount <= 0 or is_dead:
		return
	statuses[status_id] = get_status_amount(status_id) + amount
	if not bool(get_meta("simulation_quiet", false)):
		print(entity_name, " 獲得狀態 ", _get_status_display_name(status_id), amount, "。")
	combat_feedback.emit(self, "%s +%d" % [_get_status_display_name(status_id), amount], Color(0.95, 0.75, 0.25))
	stats_changed.emit(self)

func get_status_amount(status_id: String) -> int:
	return int(statuses.get(status_id, 0))

func get_status_summary() -> String:
	var parts: Array[String] = []
	for status_id in statuses.keys():
		var amount = get_status_amount(str(status_id))
		if amount > 0:
			parts.append("%s%d" % [_get_status_display_name(str(status_id)), amount])
	return " ".join(parts)

func apply_end_of_turn_statuses() -> void:
	trigger_end_of_turn_statuses()
	decay_statuses()


func trigger_end_of_turn_statuses() -> void:
	if is_dead:
		return
	var regen_amount = get_status_amount("regen")
	if regen_amount > 0:
		heal(regen_amount)
	var poison_amount = get_status_amount("poison")
	if poison_amount > 0:
		take_damage(poison_amount)


func decay_statuses() -> void:
	if statuses.is_empty():
		return
	var next_statuses := {}
	for status_id in statuses.keys():
		var next_amount = get_status_amount(str(status_id)) - 1
		if next_amount > 0:
			next_statuses[status_id] = next_amount
	statuses = next_statuses
	stats_changed.emit(self)

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

func _die() -> void:
	if is_dead:
		return
	is_dead = true
	if not bool(get_meta("simulation_quiet", false)):
		print(entity_name, " 已死亡。")
	died.emit(self)
