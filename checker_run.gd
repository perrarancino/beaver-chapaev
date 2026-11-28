extends RefCounted

enum RoundResult { PLAYER, BEAVER, DRAW }

const ROUNDS_PER_MATCH := 3
const WINS_TO_FINISH := 2
const REWARDS: Array[Checker.Icon] = [
	Checker.Icon.GHOST, Checker.Icon.EXPLOSIVE, Checker.Icon.ARMORED,
	Checker.Icon.SNOWFLAKE, Checker.Icon.FLOATING, Checker.Icon.LIGHTNING, Checker.Icon.STICKY,
	Checker.Icon.RUBBER,
]

const ACTION_MULTIPLIERS := [1.0, 1.2, 1.5, 2.0, 2.7, 3.9]

var score := 0
var streak := 0
var actions := 0

var stage := 1
var round_results: Array[RoundResult] = []
var completed_turns := 0
var roster: Array[Checker.Icon] = []
var rng: RandomNumberGenerator


func start(initial: Array[Checker.Icon], random: RandomNumberGenerator) -> void:
	score = 0
	streak = 0
	begin_player_turn()
	rng = random
	stage = 1
	round_results.clear()
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


func action_multiplier() -> float:
	return ACTION_MULTIPLIERS[clampi(actions - 1, 0, ACTION_MULTIPLIERS.size() - 1)]


func award(knockout: bool) -> int:
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


func finish_round(result: RoundResult) -> void:
	if result != RoundResult.DRAW:
		round_results.append(result)


func player_wins() -> int:
	return round_results.count(RoundResult.PLAYER)


func beaver_wins() -> int:
	return round_results.count(RoundResult.BEAVER)


func match_finished() -> bool:
	return player_wins() == WINS_TO_FINISH or beaver_wins() == WINS_TO_FINISH


func next_opening_side() -> int:
	# A drawn round does not change who opens the replay.
	return 1 if not round_results.is_empty() and round_results.back() == RoundResult.PLAYER else 0
