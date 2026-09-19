class_name EnemyCard
extends Control

signal target_requested(enemy: Entity)

const TARGET_FRAME_OUTSET := Vector2(8, 5)
const TARGET_CORNER_ARM := 13.0

@onready var name_label: Label = $VBox/Header/Name
@onready var target_marker: Label = $VBox/Header/TargetMarker
@onready var portrait: TextureRect = $VBox/Portrait
@onready var hp_bar: ProgressBar = $VBox/HPRow/HP
@onready var armor_overlay: Panel = $VBox/HPRow/ArmorOverlay
@onready var stats_label: Label = $VBox/HPRow/Stats
@onready var intent_label: Label = $VBox/Intent
@onready var status_icons: StatusIconRow = $VBox/StatusIcons
@onready var target_button: Button = $VBox/Target
@onready var target_frame: Control = $TargetFrame

var entity: Entity
var _selected := false


func _ready() -> void:
	target_button.pressed.connect(func(): target_requested.emit(entity))
	gui_input.connect(_on_gui_input)
	portrait.resized.connect(_defer_target_frame_sync)
	resized.connect(_defer_target_frame_sync)
	target_frame.draw.connect(_draw_target_frame)
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
	_update_armor_overlay(entity.hp, entity.armor, entity.max_hp)
	stats_label.text = "%d / %d%s" % [entity.hp, entity.max_hp, "　護盾 %d" % entity.armor if entity.armor > 0 else ""]
	var intent_id := str(entity.get_meta("intent_id", ""))
	var glyph := CombatIconRegistry.intent_glyph(intent_id)
	intent_label.text = "%s  %s" % [glyph, CombatIconRegistry.intent_label(intent_id)]
	intent_label.tooltip_text = "下一步：%s" % CombatIconRegistry.intent_label(intent_id)
	status_icons.refresh(entity)
	tooltip_text = "%s\n%s\n點擊角色鎖定" % [intent_label.tooltip_text, entity.get_status_summary()]
	# 活著的鎖定狀態只用立繪四角標示，避免同時出現兩套目標符號。
	target_marker.text = "†" if entity.is_dead else ""
	target_button.text = "目前目標" if selected else "鎖定此敵人"
	target_button.disabled = selected or entity.is_dead
	modulate = Color(0.45, 0.45, 0.45) if entity.is_dead else Color.WHITE
	_selected = selected and not entity.is_dead
	_sync_target_frame()
	_defer_target_frame_sync()


func _update_armor_overlay(hp: int, armor: int, maximum: int) -> void:
	armor_overlay.visible = armor > 0 and maximum > 0
	if not armor_overlay.visible:
		return
	var hp_edge := clampf(float(hp) / float(maximum), 0.0, 1.0)
	armor_overlay.anchor_left = clampf(hp_edge - float(armor) / float(maximum), 0.0, hp_edge)
	armor_overlay.anchor_right = hp_edge
	armor_overlay.offset_left = 0.0
	armor_overlay.offset_right = 0.0


func _defer_target_frame_sync() -> void:
	if is_inside_tree():
		call_deferred("_sync_target_frame")


func _sync_target_frame() -> void:
	if target_frame == null or portrait == null or not is_instance_valid(target_frame) or not is_instance_valid(portrait):
		return
	# 四角略微包在立繪外側，與敵人保留呼吸空間；短角線避免壓到名稱與 HP。
	var portrait_origin := get_global_transform_with_canvas().affine_inverse() * (portrait.get_global_transform_with_canvas() * Vector2.ZERO)
	target_frame.position = portrait_origin - TARGET_FRAME_OUTSET
	target_frame.size = (portrait.size + TARGET_FRAME_OUTSET * 2.0).max(Vector2(16, 16))
	target_frame.visible = _selected
	target_frame.queue_redraw()


func _draw_target_frame() -> void:
	if not _selected or not target_frame.visible:
		return
	var color := Color("f7d889")
	var arm := TARGET_CORNER_ARM
	var left := 0.0
	var top := 0.0
	var right := target_frame.size.x
	var bottom := target_frame.size.y
	for points in [
		[Vector2(left, top + arm), Vector2(left, top), Vector2(left + arm, top)],
		[Vector2(right - arm, top), Vector2(right, top), Vector2(right, top + arm)],
		[Vector2(left, bottom - arm), Vector2(left, bottom), Vector2(left + arm, bottom)],
		[Vector2(right - arm, bottom), Vector2(right, bottom), Vector2(right, bottom - arm)],
	]:
		target_frame.draw_polyline(PackedVector2Array(points), Color(0.01, 0.015, 0.025, 0.94), 8.0, false)
		target_frame.draw_polyline(PackedVector2Array(points), color, 4.0, false)


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
