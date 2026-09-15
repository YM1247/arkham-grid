class_name UIThemeFactory
extends RefCounted


static func build(document: Dictionary) -> Theme:
	var theme := Theme.new()
	var pixel_font := load("res://assets/fonts/fusion-pixel-12px-zh_hant.ttf") as FontFile
	var palette: Dictionary = document.get("palette", {})
	var typography: Dictionary = document.get("typography", {})
	var spacing: Dictionary = document.get("spacing", {})
	var radius := mini(int(document.get("shape", {}).get("corner_radius", 8)), 2)
	var border_width := int(document.get("shape", {}).get("border_width", 2))
	var text := _color(palette, "text", Color("f1ebdd"))
	var muted := _color(palette, "muted", Color("9ca9bb"))
	var panel := _color(palette, "panel", Color("182131"))
	var hover := _color(palette, "panel_hover", Color("223047"))
	var border := _color(palette, "border", Color("3b4b63"))
	var accent := _color(palette, "accent", Color("e6b95c"))
	var focus := _color(palette, "focus", Color("f7d889"))

	theme.default_font_size = int(typography.get("body", 18))
	for type in ["Label", "Button", "CheckButton", "OptionButton"]:
		theme.set_color("font_color", type, text)
		theme.set_color("font_disabled_color", type, muted.darkened(0.25))
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_focus_color", "Button", Color.WHITE)
	theme.set_color("font_color", "TooltipLabel", text)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.7))
	theme.set_constant("shadow_offset_x", "Label", 2)
	theme.set_constant("shadow_offset_y", "Label", 2)
	theme.set_constant("separation", "VBoxContainer", int(spacing.get("sm", 10)))
	theme.set_constant("separation", "HBoxContainer", int(spacing.get("sm", 10)))
	theme.set_constant("h_separation", "GridContainer", int(spacing.get("xs", 6)))
	theme.set_constant("v_separation", "GridContainer", int(spacing.get("xs", 6)))
	theme.set_font_size("font_size", "TooltipLabel", int(typography.get("caption", 15)))
	if pixel_font != null:
		# 常態介面統一採像素字；密集效果內文則由個別元件覆寫為易讀字體。
		theme.set_font("font", "Label", pixel_font)
		theme.set_font("font", "Button", pixel_font)
		theme.set_font("font", "CheckButton", pixel_font)
		theme.set_font("font", "OptionButton", pixel_font)
		theme.set_font("font", "ProgressBar", pixel_font)

	theme.set_stylebox("panel", "PanelContainer", _box(panel, border, radius, border_width, 10))
	theme.set_stylebox("panel", "TooltipPanel", _box(panel, accent, radius, 1, 8))
	theme.set_stylebox("normal", "Button", _box(panel, border, radius, border_width, 8))
	theme.set_stylebox("hover", "Button", _box(hover, accent, radius, border_width, 8))
	theme.set_stylebox("pressed", "Button", _box(palette.get("accent_dark", "#8B6532"), accent, radius, border_width, 8))
	theme.set_stylebox("disabled", "Button", _box(panel.darkened(0.3), border.darkened(0.35), radius, 1, 8))
	theme.set_stylebox("focus", "Button", _outline(focus, radius, 3))
	theme.set_stylebox("normal", "ProgressBar", _box(_color(palette, "surface", Color("111724")), border, radius, 1, 0))
	theme.set_stylebox("fill", "ProgressBar", _box(accent, accent, radius, 0, 0))
	theme.set_stylebox("grabber_area", "HSlider", _box(accent, accent, radius, 0, 0))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _box(focus, focus, radius, 0, 0))
	return theme


static func color(document: Dictionary, key: String, fallback: Color = Color.WHITE) -> Color:
	return _color(document.get("palette", {}), key, fallback)


static func _color(palette: Dictionary, key: String, fallback: Color) -> Color:
	var value := str(palette.get(key, ""))
	return Color(value) if Color.html_is_valid(value) else fallback


static func _box(background, border: Color, radius: int, width: int, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background if background is Color else Color(str(background))
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_top = padding
	style.content_margin_right = padding
	style.content_margin_bottom = padding
	return style


static func _outline(color: Color, radius: int, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = color
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.expand_margin_left = 2
	style.expand_margin_top = 2
	style.expand_margin_right = 2
	style.expand_margin_bottom = 2
	return style
