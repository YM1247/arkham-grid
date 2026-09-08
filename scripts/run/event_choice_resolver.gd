class_name EventChoiceResolver
extends RefCounted

const RESOURCE_LABELS := {
	"hp": "HP",
	"sanity": "Sanity",
	"mp": "MP",
	"currency": "金錢",
}
const RESOURCE_KEYS := ["hp", "sanity", "mp", "currency"]


func preview_choices(event_definition: Dictionary, state: Dictionary) -> Array[Dictionary]:
	var previews: Array[Dictionary] = []
	for option in event_definition.get("options", []):
		if option is Dictionary:
			previews.append(preview_choice(option, state))
	return previews


func preview_choice(option: Dictionary, state: Dictionary) -> Dictionary:
	var option_id := str(option.get("id", ""))
	if option_id.is_empty():
		return {"valid": false, "affordable": false, "reason": "選項缺少 ID"}
	var costs = option.get("costs", {})
	var results = option.get("results", {})
	if not costs is Dictionary or not results is Dictionary:
		return {"valid": false, "affordable": false, "reason": "代價或結果格式不合法"}
	var changes := {}
	var deltas := {}
	var affordable := true
	var reason := ""
	for key in RESOURCE_KEYS:
		var current := int(state.get(key, 0))
		var cost := int(costs.get(key, 0))
		var reward := int(results.get(key, 0))
		if cost < 0 or reward < 0:
			return {"valid": false, "affordable": false, "reason": "%s 不可為負數" % RESOURCE_LABELS[key]}
		var minimum_remaining := 1 if key in ["hp", "sanity"] else 0
		if current - cost < minimum_remaining:
			affordable = false
			reason = "%s 不足" % RESOURCE_LABELS[key]
		var maximum := int(state.get("max_%s" % key, current - cost + reward))
		var final_value := current - cost + reward
		if key in ["hp", "sanity", "mp"]:
			final_value = mini(final_value, maximum)
		changes[key] = maxi(final_value, 0)
		deltas[key] = int(changes[key]) - current
	return {
		"valid": true,
		"affordable": affordable,
		"reason": reason,
		"option_id": option_id,
		"label": str(option.get("label", option_id)),
		"description": str(option.get("description", "")),
		"result_text": str(option.get("result_text", "")),
		"costs": costs.duplicate(true),
		"results": results.duplicate(true),
		"changes": changes,
		"deltas": deltas,
		"summary": _format_summary(costs, results),
	}


func resolve_choice(event_definition: Dictionary, option_id: String, state: Dictionary) -> Dictionary:
	for option in event_definition.get("options", []):
		if option is Dictionary and str(option.get("id", "")) == option_id:
			return preview_choice(option, state)
	return {"valid": false, "affordable": false, "reason": "找不到事件選項：%s" % option_id}


func _format_summary(costs: Dictionary, results: Dictionary) -> String:
	var parts: Array[String] = []
	for key in RESOURCE_KEYS:
		var amount := int(costs.get(key, 0))
		if amount > 0:
			parts.append("消耗 %s %d" % [RESOURCE_LABELS[key], amount])
	for key in RESOURCE_KEYS:
		var amount := int(results.get(key, 0))
		if amount > 0:
			parts.append("獲得 %s %d" % [RESOURCE_LABELS[key], amount])
	return "｜".join(parts) if not parts.is_empty() else "不消耗資源"
