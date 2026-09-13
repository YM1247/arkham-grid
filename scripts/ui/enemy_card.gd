class_name EnemyCard
extends PanelContainer

signal target_requested(enemy: Entity)

@onready var name_label: Label = $VBox/Header/Name
@onready var target_marker: Label = $VBox/Header/TargetMarker
@onready var hp_bar: ProgressBar = $VBox/HPRow/HP
@onready var stats_label: Label = $VBox/HPRow/Stats
@onready var intent_label: Label = $VBox/Intent
@onready var status_label: Label = $VBox/Status
@onready var target_button: Button = $VBox/Target

var entity: Entity


func _ready() -> void:
	target_button.pressed.connect(func(): target_requested.emit(entity))
	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = Color("d95c64")
	hp_fill.set_corner_radius_all(5)
	hp_bar.add_theme_stylebox_override("fill", hp_fill)


func bind(value: Entity) -> void:
	entity = value
	refresh(false)


func refresh(selected: bool) -> void:
	if entity == null:
		visible = false
		return
	visible = true
	name_label.text = entity.entity_name
	hp_bar.max_value = maxi(entity.max_hp, 1)
	hp_bar.value = entity.hp
	stats_label.text = "%d/%d　甲 %d" % [entity.hp, entity.max_hp, entity.armor]
	var status := entity.get_status_summary()
	status_label.text = "狀態｜%s" % ("無" if status.is_empty() else status)
	intent_label.text = "下一步　%s" % str(entity.get_meta("intent_display", "--"))
	target_marker.text = "◆ 目前目標" if selected else ""
	target_button.text = "目前目標" if selected else "鎖定此敵人"
	target_button.disabled = selected or entity.is_dead
	modulate = Color(0.45, 0.45, 0.45) if entity.is_dead else Color.WHITE


func get_feedback_anchor() -> Label:
	return stats_label
