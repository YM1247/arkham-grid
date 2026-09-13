class_name UIMotion
extends RefCounted

static var fast_seconds := 0.08
static var normal_seconds := 0.16
static var emphasis_seconds := 0.28


static func configure(document: Dictionary) -> void:
	var motion: Dictionary = document.get("motion", {})
	fast_seconds = float(motion.get("fast_seconds", fast_seconds))
	normal_seconds = float(motion.get("normal_seconds", normal_seconds))
	emphasis_seconds = float(motion.get("emphasis_seconds", emphasis_seconds))


static func fade_in(control: Control, timing: String = "normal") -> void:
	if control == null or not control.is_inside_tree():
		return
	control.modulate.a = 0.0
	control.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(control, "modulate:a", 1.0, _duration(timing))


static func _duration(timing: String) -> float:
	match timing:
		"fast": return fast_seconds
		"emphasis": return emphasis_seconds
		_: return normal_seconds
