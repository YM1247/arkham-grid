extends Control

var _time := 0.0
var _motes: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 1701
	for index in range(18):
		_motes.append({
			"x": rng.randf(),
			"y": rng.randf_range(0.48, 0.94),
			"radius": rng.randf_range(18.0, 54.0),
			"speed": rng.randf_range(0.006, 0.018),
			"phase": rng.randf_range(0.0, TAU),
		})


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var area := size
	for mote in _motes:
		var x := fposmod(float(mote.x) + _time * float(mote.speed), 1.14) - 0.07
		var y := float(mote.y) + sin(_time * 0.24 + float(mote.phase)) * 0.018
		draw_circle(Vector2(x * area.x, y * area.y), float(mote.radius), Color(0.24, 0.43, 0.49, 0.018))
	for inset in range(12):
		var margin := float(inset * 12)
		var alpha := 0.018 + float(11 - inset) * 0.003
		draw_rect(Rect2(Vector2(margin, margin), area - Vector2(margin * 2.0, margin * 2.0)), Color(0.0, 0.0, 0.0, alpha), false, 24.0)
