class_name EnemyRosterPresenter
extends RefCounted

const ENEMY_CARD_SCENE = preload("res://scenes/enemy_card.tscn")

var _cards: Array[EnemyCard] = []
var _roster_ids: Array[int] = []
var _enemy_indices: Array[int] = []
var _selected_callback: Callable


func render(label: Label, enemies: Array[Entity], selected_index: int, selected_callback: Callable) -> void:
	if label == null:
		return
	label.visible = false
	var container := label.get_parent()
	if container == null:
		return
	var roster_ids: Array[int] = []
	for enemy in enemies:
		if enemy != null:
			roster_ids.append(enemy.get_instance_id())
	if roster_ids != _roster_ids:
		_rebuild(container, enemies, selected_callback)
	for i in range(_cards.size()):
		_cards[i].refresh(_enemy_indices[i] == selected_index)


func clear() -> void:
	for card in _cards:
		if is_instance_valid(card):
			card.queue_free()
	_cards.clear()
	_roster_ids.clear()
	_enemy_indices.clear()


func get_feedback_anchor(entity: Entity) -> Label:
	for card in _cards:
		if card.entity == entity:
			return card.get_feedback_anchor()
	return null


func get_card_instance_ids() -> Array[int]:
	var ids: Array[int] = []
	for card in _cards:
		ids.append(card.get_instance_id())
	return ids


func play_windup(entity: Entity) -> void:
	var card := _find_card(entity)
	if card != null:
		await card.play_windup()


func play_resolution(entity: Entity) -> void:
	var card := _find_card(entity)
	if card != null:
		await card.play_resolution()


func play_return(entity: Entity) -> void:
	var card := _find_card(entity)
	if card != null:
		await card.play_return()


func play_hit(entity: Entity) -> void:
	var card := _find_card(entity)
	if card != null:
		card.play_hit()


func play_death(entity: Entity) -> void:
	var card := _find_card(entity)
	if card != null:
		card.play_death()


func _find_card(entity: Entity) -> EnemyCard:
	for card in _cards:
		if card.entity == entity:
			return card
	return null


func _rebuild(container: Node, enemies: Array[Entity], selected_callback: Callable) -> void:
	clear()
	_selected_callback = selected_callback
	for enemy_index in range(enemies.size()):
		var enemy := enemies[enemy_index]
		if enemy == null:
			continue
		var card := ENEMY_CARD_SCENE.instantiate() as EnemyCard
		container.add_child(card)
		card.bind(enemy)
		card.pivot_offset = card.custom_minimum_size * 0.5
		card.scale = Vector2(0.92, 0.92)
		card.self_modulate = Color(0.84, 0.9, 0.94, 1.0)
		card.target_requested.connect(_on_target_requested)
		_cards.append(card)
		_roster_ids.append(enemy.get_instance_id())
		_enemy_indices.append(enemy_index)


func _on_target_requested(entity: Entity) -> void:
	if not _selected_callback.is_valid():
		return
	for i in range(_cards.size()):
		if _cards[i].entity == entity:
			_selected_callback.call(_enemy_indices[i])
			return
