class_name EnemyCard
extends PanelContainer

signal target_requested(enemy: Entity)

@onready var name_label: Label = $VBox/Header/Name
@onready var target_marker: Label = $VBox/Header/TargetMarker
@onready var portrait: TextureRect = $VBox/Portrait
@onready var hp_bar: ProgressBar = $VBox/HPRow/HP
@onready var stats_label: Label = $VBox/HPRow/Stats
@onready var intent_label: Label = $VBox/Intent
@onready var status_label: Label = $VBox/Status
@onready var target_button: Button = $VBox/Target

var entity: Entity


func _ready() -> void:
	target_button.pressed.connect(func(): target_requested.emit(entity))
	gui_input.connect(_on_gui_input)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = Color("d95c64")
	hp_fill.set_corner_radius_all(5)
	hp_bar.add_theme_stylebox_override("fill", hp_fill)


func bind(value: Entity) -> void:
	entity = value
	var art_path := str(entity.get_meta("art_path", ""))
	portrait.texture = load(art_path) if not art_path.is_empty() and ResourceLoader.exists(art_path) else null
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
	tooltip_text = "%s\n%s\n點擊卡片鎖定" % [intent_label.text, status_label.text]
	target_marker.text = "†" if entity.is_dead else "◆" if selected else ""
	target_button.text = "目前目標" if selected else "鎖定此敵人"
	target_button.disabled = selected or entity.is_dead
	modulate = Color(0.45, 0.45, 0.45) if entity.is_dead else Color.WHITE


func play_windup() -> void:
	pivot_offset = size * 0.5
	z_index = 10
	var tween := create_tween()
	tween.parallel().tween_property(self, "scale", Vector2(1.06, 1.06), 0.16).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(self, "self_modulate", Color("f6d889"), 0.12)
	await tween.finished


func play_resolution() -> void:
	var tween := create_tween()
	tween.tween_property(portrait, "modulate", Color.WHITE * 1.35, 0.05)
	tween.tween_property(portrait, "modulate", Color.WHITE, 0.12)
	await tween.finished


func play_return() -> void:
	var tween := create_tween()
	tween.parallel().tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(self, "self_modulate", Color.WHITE, 0.18)
	await tween.finished
	z_index = 0


func play_hit() -> void:
	portrait.pivot_offset = portrait.size * 0.5
	var tween := create_tween()
	tween.parallel().tween_property(portrait, "rotation", -0.055, 0.05)
	tween.parallel().tween_property(portrait, "modulate", Color("ff8a8a"), 0.05)
	tween.tween_property(portrait, "rotation", 0.045, 0.06)
	tween.tween_property(portrait, "rotation", 0.0, 0.06)
	tween.parallel().tween_property(portrait, "modulate", Color.WHITE, 0.12)


func play_death() -> void:
	portrait.pivot_offset = portrait.size * 0.5
	var tween := create_tween()
	tween.parallel().tween_property(portrait, "scale", Vector2(0.78, 0.78), 0.32).set_trans(Tween.TRANS_QUAD)
	tween.parallel().tween_property(portrait, "rotation", 0.06, 0.32)
	tween.parallel().tween_property(portrait, "modulate:a", 0.1, 0.32)
	target_marker.text = "†"


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if entity != null and not entity.is_dead:
			target_requested.emit(entity)


func get_feedback_anchor() -> Label:
	return stats_label
