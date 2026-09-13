class_name PlayerHUD
extends PanelContainer

@onready var name_label: Label = $VBox/Header/Name
@onready var armor_label: Label = $VBox/Header/Armor
@onready var hp_bar: ProgressBar = $VBox/HP/Bar
@onready var hp_value: Label = $VBox/HP/Value
@onready var sanity_bar: ProgressBar = $VBox/Sanity/Bar
@onready var sanity_value: Label = $VBox/Sanity/Value
@onready var mp_bar: ProgressBar = $VBox/MP/Bar
@onready var mp_value: Label = $VBox/MP/Value
@onready var status_label: Label = $VBox/Status
@onready var recent_label: Label = $VBox/Recent


func _ready() -> void:
	_set_fill_color(hp_bar, Color("d95c64"))
	_set_fill_color(sanity_bar, Color("a77ae5"))
	_set_fill_color(mp_bar, Color("5ca9e6"))


func refresh(entity: Entity, mp: int, max_mp: int, sanity_stage: String, sanity_effects: String, recent_change: String) -> void:
	if entity == null:
		return
	name_label.text = entity.entity_name
	armor_label.text = "護甲 %d" % entity.armor
	_set_bar(hp_bar, hp_value, entity.hp, entity.max_hp)
	_set_bar(sanity_bar, sanity_value, entity.sanity, entity.max_sanity)
	_set_bar(mp_bar, mp_value, mp, max_mp)
	var statuses: Array[String] = []
	if entity.has_method("get_status_summary"):
		var summary := str(entity.get_status_summary())
		if not summary.is_empty():
			statuses.append(summary)
	if not sanity_effects.is_empty():
		statuses.append("%s｜%s" % [sanity_stage, sanity_effects])
	status_label.text = "狀態｜%s" % ("穩定" if statuses.is_empty() else "　".join(statuses))
	recent_label.visible = not recent_change.is_empty()
	recent_label.text = "最近理智變化｜%s" % recent_change


func _set_bar(bar: ProgressBar, value_label: Label, value: int, maximum: int) -> void:
	bar.max_value = maxi(maximum, 1)
	bar.value = clampi(value, 0, maximum)
	value_label.text = "%d / %d" % [value, maximum]


func _set_fill_color(bar: ProgressBar, color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("fill", style)
