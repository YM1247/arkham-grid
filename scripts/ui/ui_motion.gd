class_name UIMotion
extends RefCounted

static var fast_seconds := 0.08
static var normal_seconds := 0.16
static var emphasis_seconds := 0.28
const TWEEN_META := &"ui_motion_tween"


static func configure(document: Dictionary) -> void:
	var motion: Dictionary = document.get("motion", {})
	fast_seconds = float(motion.get("fast_seconds", fast_seconds))
	normal_seconds = float(motion.get("normal_seconds", normal_seconds))
	emphasis_seconds = float(motion.get("emphasis_seconds", emphasis_seconds))


static func fade_in(control: Control, timing: String = "normal") -> void:
	if control == null or not control.is_inside_tree():
		return
	_cancel_active_tween(control)
	control.visible = true
	control.modulate.a = 0.0
	var tween := control.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	control.set_meta(TWEEN_META, tween)
	tween.tween_property(control, "modulate:a", 1.0, _duration(timing))
	tween.tween_callback(func(): control.remove_meta(TWEEN_META))


static func fade_out(control: Control, on_finished: Callable = Callable(), timing: String = "normal") -> void:
	if control == null or not control.is_inside_tree() or not control.visible:
		if on_finished.is_valid():
			on_finished.call()
		return
	_cancel_active_tween(control)
	var tween := control.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	control.set_meta(TWEEN_META, tween)
	tween.tween_property(control, "modulate:a", 0.0, _duration(timing))
	tween.tween_callback(func():
		control.visible = false
		control.modulate.a = 1.0
		control.remove_meta(TWEEN_META)
		if on_finished.is_valid():
			on_finished.call()
	)


static func _cancel_active_tween(control: Control) -> void:
	if not control.has_meta(TWEEN_META):
		return
	var active = control.get_meta(TWEEN_META)
	if active is Tween and active.is_valid():
		active.kill()
	control.remove_meta(TWEEN_META)


static func _duration(timing: String) -> float:
	match timing:
		"fast": return fast_seconds
		"emphasis": return emphasis_seconds
		_: return normal_seconds
