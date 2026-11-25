extends RefCounted

const STAGES := 8
const REWARDS: Array[Checker.Icon] = [
	Checker.Icon.GHOST, Checker.Icon.EXPLOSIVE, Checker.Icon.ARMORED,
	Checker.Icon.SNOWFLAKE, Checker.Icon.FLOATING, Checker.Icon.LIGHTNING, Checker.Icon.STICKY,
	Checker.Icon.RUBBER,
]

const ACTION_MULTIPLIERS := [1.0, 1.2, 1.5, 2.0, 2.7, 3.9]

var score := 0
var streak := 0
var actions := 0
var hit_slots: Dictionary[int, bool] = {}

var stage := 1
var wins := 0
var completed_turns := 0
var roster: Array[Checker.Icon] = []
var rng: RandomNumberGenerator


func start(initial: Array[Checker.Icon], random: RandomNumberGenerator) -> void:
	score = 0
	streak = 0
	begin_player_turn()
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


func begin_player_turn() -> void:
	actions = 0
	hit_slots.clear()


func action_multiplier() -> float:
	return ACTION_MULTIPLIERS[clampi(actions - 1, 0, ACTION_MULTIPLIERS.size() - 1)]


func award(slot: int, knockout: bool) -> int:
	if not knockout:
		if hit_slots.has(slot):
			return 0
		hit_slots[slot] = true
	if actions == 0:
		streak += 1
	actions += 1
	var base := 500 if knockout else 100
	var points := roundi(base * action_multiplier() * streak)
	score += points
	return points


func finish_turn(player_turn: bool) -> void:
	if player_turn and actions == 0:
		streak = 0
	completed_turns += 1


func finish_round(won: bool) -> void:
	if won:
		wins += 1
