extends RefCounted

const STAGES := 8
const REWARDS: Array[Checker.Icon] = [
	Checker.Icon.GHOST, Checker.Icon.EXPLOSIVE, Checker.Icon.ARMORED,
	Checker.Icon.SNOWFLAKE, Checker.Icon.FLOATING, Checker.Icon.LIGHTNING, Checker.Icon.STICKY,
	Checker.Icon.RUBBER,
]

var stage := 1
var wins := 0
var completed_turns := 0
var roster: Array[Checker.Icon] = []
var rng: RandomNumberGenerator


func start(initial: Array[Checker.Icon], random: RandomNumberGenerator) -> void:
	rng = random
	stage = 1
	wins = 0
	completed_turns = 0
	roster = initial.duplicate()


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
	if Checker.Icon.NONE not in roster:
		for icon in REWARDS:
			if _reward_slot(icon) < 0:
				pool.erase(icon)
	var rewards: Array[Checker.Icon] = []
	for i in mini(3, pool.size()):
		var index := rng.randi_range(0, pool.size() - 1)
		rewards.append(pool[index])
		pool.remove_at(index)
	return rewards


func choose(icon: Checker.Icon) -> void:
	var slot := _reward_slot(icon)
	if slot >= 0:
		roster[slot] = icon
	stage += 1


func _reward_slot(icon: Checker.Icon) -> int:
	var slot := roster.find(Checker.Icon.NONE)
	if slot >= 0:
		return slot
	for i in range(roster.size() - 1, -1, -1):
		if roster[i] != icon and roster.count(roster[i]) > 1:
			return i
	return -1


func finish_turn() -> void:
	completed_turns += 1


func finish_round(won: bool) -> void:
	if won:
		wins += 1
