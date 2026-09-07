class_name EnemyCard
extends VBoxContainer

signal target_requested(enemy: Entity)

@onready var name_label: Label = $Name
@onready var stats_label: Label = $Stats
@onready var intent_label: Label = $Intent
@onready var target_button: Button = $Target

var entity: Entity


func _ready() -> void:
	target_button.pressed.connect(func(): target_requested.emit(entity))


func bind(value: Entity) -> void:
	entity = value
	refresh(false)


func refresh(selected: bool) -> void:
	if entity == null:
		visible = false
		return
	visible = true
	name_label.text = entity.entity_name
	stats_label.text = "HP %d/%d｜護甲 %d" % [entity.hp, entity.max_hp, entity.armor]
	var status := entity.get_status_summary()
	if not status.is_empty():
		stats_label.text += "｜%s" % status
	intent_label.text = "意圖：%s" % str(entity.get_meta("intent_display", "--"))
	target_button.text = "已鎖定" if selected else "鎖定"
	target_button.disabled = selected or entity.is_dead
	modulate = Color(0.55, 0.55, 0.55) if entity.is_dead else Color.WHITE


func get_feedback_anchor() -> Label:
	return stats_label
