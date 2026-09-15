class_name SpellRuneBadge
extends Control

const DEFAULT_COLOR := Color("d7c77b")

var category_id := "single_attack"
var glyph := "✦"
var text := "✦"
var accent_color := DEFAULT_COLOR
var corner_marker := ""
var _glyph_label: Label
var _corner_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_labels()
	_refresh_labels()
	queue_redraw()


func configure(spell: BattleItem, marker: String = "") -> void:
	category_id = spell.category_id if spell != null else ""
	glyph = spell.category_glyph if spell != null and not spell.category_glyph.is_empty() else "✦"
	text = glyph
	accent_color = spell.get_icon_color() if spell != null else DEFAULT_COLOR
	corner_marker = marker if not marker.is_empty() else _scope_marker(spell.effect_scope if spell != null else "")
	tooltip_text = spell.get_effect_tooltip("石板咒文") if spell != null else ""
	_ensure_labels()
	_refresh_labels()
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	draw_style_box(_badge_style(), rect)
	draw_circle(Vector2(size.x * 0.5, size.y * 0.5), maxf(minf(size.x, size.y) * 0.34, 4.0), Color(accent_color, 0.12))


func _ensure_labels() -> void:
	if _glyph_label == null:
		_glyph_label = Label.new()
		_glyph_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_glyph_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_glyph_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_glyph_label)
	if _corner_label == null:
		_corner_label = Label.new()
		_corner_label.anchor_left = 0.58
		_corner_label.anchor_top = 0.58
		_corner_label.anchor_right = 0.96
		_corner_label.anchor_bottom = 0.96
		_corner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_corner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_corner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_corner_label)


func _refresh_labels() -> void:
	if _glyph_label == null:
		return
	_glyph_label.text = glyph
	_glyph_label.add_theme_font_size_override("font_size", maxi(10, int(minf(size.x, size.y) * 0.58)))
	_glyph_label.add_theme_color_override("font_color", accent_color)
	_glyph_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_glyph_label.add_theme_constant_override("shadow_offset_x", 2)
	_glyph_label.add_theme_constant_override("shadow_offset_y", 2)
	_corner_label.text = corner_marker
	_corner_label.add_theme_font_size_override("font_size", maxi(7, int(minf(size.x, size.y) * 0.26)))
	_corner_label.add_theme_color_override("font_color", Color.WHITE)


func _badge_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.07, 0.92)
	style.border_color = accent_color
	style.set_border_width_all(2 if minf(size.x, size.y) < 34.0 else 3)
	style.set_corner_radius_all(maxi(3, int(minf(size.x, size.y) * 0.2)))
	return style


func _scope_marker(scope: String) -> String:
	match scope:
		"spread": return "3"
		"all": return "∞"
		"self": return "自"
		_: return ""
