class_name BoardModel
extends RefCounted

var dimension: int
var cells: Array = []


func _init(size: int = 8) -> void:
	dimension = size
	clear()


func clear() -> void:
	cells.clear()
	for x in range(dimension):
		var column: Array = []
		column.resize(dimension)
		column.fill(null)
		cells.append(column)


func can_place(origin_x: int, origin_y: int, offsets: Array[Vector2i]) -> bool:
	for offset in offsets:
		var x := origin_x + offset.x
		var y := origin_y + offset.y
		if x < 0 or x >= dimension or y < 0 or y >= dimension:
			return false
		if cells[x][y] != null:
			return false
	return true


func place(origin_x: int, origin_y: int, offsets: Array[Vector2i], value) -> Dictionary:
	if not can_place(origin_x, origin_y, offsets):
		return {"placed": false, "rows": [], "cols": []}
	for offset in offsets:
		cells[origin_x + offset.x][origin_y + offset.y] = value
	var lines := get_full_lines()
	return {"placed": true, "rows": lines.rows, "cols": lines.cols}


func get_full_lines(extra_cells: Dictionary = {}) -> Dictionary:
	var rows: Array[int] = []
	var cols: Array[int] = []
	for y in range(dimension):
		var full := true
		for x in range(dimension):
			if cells[x][y] == null and not extra_cells.has(Vector2i(x, y)):
				full = false
				break
		if full:
			rows.append(y)
	for x in range(dimension):
		var full := true
		for y in range(dimension):
			if cells[x][y] == null and not extra_cells.has(Vector2i(x, y)):
				full = false
				break
		if full:
			cols.append(x)
	return {"rows": rows, "cols": cols}


func clear_lines(rows: Array, cols: Array) -> void:
	for y in rows:
		for x in range(dimension):
			cells[x][int(y)] = null
	for x in cols:
		for y in range(dimension):
			cells[int(x)][y] = null


func serialize_cells() -> Array[String]:
	var serialized: Array[String] = []
	for y in range(dimension):
		for x in range(dimension):
			var value = cells[x][y]
			serialized.append(value.to_html(true) if value is Color else "")
	return serialized


func restore_cells(serialized: Array[String]) -> bool:
	if serialized.size() != dimension * dimension:
		return false
	clear()
	for index in range(serialized.size()):
		var value := serialized[index]
		if not value.is_empty():
			cells[index % dimension][index / dimension] = Color.html(value)
	return true
