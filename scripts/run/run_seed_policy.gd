class_name RunSeedPolicy
extends RefCounted

const MIN_RUNTIME_SEED := 1
const MAX_RUNTIME_SEED := 2147483646
const MODES := ["random", "fixed"]


func choose_seed(config: Dictionary, previous_seed: int = 0, source: RandomNumberGenerator = null) -> int:
	var mode := str(config.get("runtime_seed_mode", "random"))
	if mode == "fixed":
		return int(config.get("seed", 424242))
	var generator := source
	if generator == null:
		generator = RandomNumberGenerator.new()
		generator.randomize()
	var next_seed := generator.randi_range(MIN_RUNTIME_SEED, MAX_RUNTIME_SEED)
	if next_seed == previous_seed:
		next_seed = MIN_RUNTIME_SEED if next_seed >= MAX_RUNTIME_SEED else next_seed + 1
	return next_seed
