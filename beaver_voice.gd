extends AudioStreamPlayer

signal subtitle_changed(text: String)

const TURN_LINES := [&"aim_first", &"aim_second", &"aim_third"]
# Each clip stores its normalized loudness as digits sampled at 40 Hz.
const ENVELOPE_FPS := 40.0
const LINES := {
	&"aim_first": [
		"Так, сейчас прицелюсь.",
		preload("res://assets/beaver/voice/aim_first.ogg"),
		"007962112112024599420000430011056323321111000000",
	],
	&"aim_second": [
		"Дай-ка примерюсь.",
		preload("res://assets/beaver/voice/aim_second.ogg"),
		"0000116871014996100347434467524332210000000",
	],
	&"aim_third": [
		"Попробую с этой стороны.",
		preload("res://assets/beaver/voice/aim_third.ogg"),
		"0089410118992115894330016410266231003735444322211000000",
	],
	&"win": [
		"Хорошая игра! Сыграем ещё?",
		preload("res://assets/beaver/voice/win.ogg"),
		"0000157589755653245423537899751000000000000000000000000122122014799998632233442334314553200000000",
	],
	&"lose": [
		"Ловко сыграно. Давай ещё раз!",
		preload("res://assets/beaver/voice/lose.ogg"),
		"0023469952100136234432563113322232100000000000000000000000045228975333234534897475422321000000",
	],
	&"draw": [
		"Ничья. Ещё раунд?",
		preload("res://assets/beaver/voice/draw.ogg"),
		"0157862587526788975210000000000000000000000022223343269997476654421100000000",
	],
}

var _turn_line := 0
var _envelope := ""


func _ready() -> void:
	finished.connect(_clear_subtitle)


func say_turn() -> void:
	say(TURN_LINES[_turn_line])
	_turn_line = (_turn_line + 1) % TURN_LINES.size()


func say(cue: StringName) -> void:
	var line: Array = LINES[cue]
	stream = line[1]
	_envelope = line[2]
	play()
	subtitle_changed.emit(line[0])


func mouth_opening() -> float:
	if not playing:
		return 0.0
	var frame := maxf(0.0, get_playback_position() * ENVELOPE_FPS)
	var first := mini(int(frame), _envelope.length() - 1)
	var next := mini(first + 1, _envelope.length() - 1)
	return lerpf(_envelope.unicode_at(first) - 48, _envelope.unicode_at(next) - 48,
		fposmod(frame, 1.0)) / 9.0


func _clear_subtitle() -> void:
	subtitle_changed.emit("")
