extends RefCounted

const STAGES := 8
const REWARDS: Array[Checker.Icon] = [
	Checker.Icon.GHOST, Checker.Icon.SNIPER, Checker.Icon.EXPLOSIVE, Checker.Icon.ARMORED,
	Checker.Icon.SNOWFLAKE, Checker.Icon.FLOATING, Checker.Icon.LIGHTNING, Checker.Icon.STICKY,
	Checker.Icon.RUBBER, Checker.Icon.VAMPIRE,
]
const STARTER_BONUSES: Array[Checker.Icon] = [
	Checker.Icon.FLOATING, Checker.Icon.LIGHTNING, Checker.Icon.STICKY, Checker.Icon.RUBBER,
	Checker.Icon.VAMPIRE,
]

var stage := 1
var wins := 0
var roster: Array[Checker.Icon] = []
var duration: Array[int] = []
var rng: RandomNumberGenerator


func start(initial: Array[Checker.Icon], random: RandomNumberGenerator) -> void:
	rng = random
	stage = 1
	wins = 0
	roster = initial.duplicate()
	duration.resize(roster.size())
	for slot in roster.size():
		duration[slot] = _duration_for(roster[slot])
	var empty := roster.find(Checker.Icon.NONE)
	if empty >= 0:
		_assign(empty, STARTER_BONUSES[rng.randi_range(0, STARTER_BONUSES.size() - 1)])


func enemies(initial: Array[Checker.Icon]) -> Array[Checker.Icon]:
	var result := initial.duplicate()
	var open_slots: Array[int] = []
	for slot in result.size():
		if result[slot] == Checker.Icon.NONE:
			open_slots.append(slot)
	for i in mini(open_slots.size(), 1 + (stage - 1) / 2):
		var index := rng.randi_range(0, open_slots.size() - 1)
		result[open_slots[index]] = REWARDS[rng.randi_range(0, REWARDS.size() - 1)]
		open_slots.remove_at(index)
	return result


func offer() -> Array[Checker.Icon]:
	var pool := REWARDS.duplicate()
	var rewards: Array[Checker.Icon] = []
	for i in 3:
		var index := rng.randi_range(0, pool.size() - 1)
		rewards.append(pool[index])
		pool.remove_at(index)
	return rewards


func choose(icon: Checker.Icon) -> void:
	var slot := roster.find(Checker.Icon.NONE)
	if slot < 0:
		slot = roster.size() - 1
	_assign(slot, icon)
	stage += 1


func finish_turn() -> void:
	_tick_duration(Checker.Icon.GHOST)


func finish_round() -> void:
	_tick_duration(Checker.Icon.FLOATING)


func _tick_duration(icon: Checker.Icon) -> void:
	for slot in roster.size():
		if roster[slot] == icon:
			duration[slot] -= 1
			if duration[slot] == 0:
				_assign(slot, Checker.Icon.NONE)


func _assign(slot: int, icon: Checker.Icon) -> void:
	roster[slot] = icon
	duration[slot] = _duration_for(icon)


func _duration_for(icon: Checker.Icon) -> int:
	match icon:
		Checker.Icon.GHOST: return 2
		Checker.Icon.FLOATING: return 3
		_: return 0
