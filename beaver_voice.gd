extends AudioStreamPlayer

signal subtitle_changed(text: String)
signal idle

# Each clip stores its normalized loudness as digits sampled at 40 Hz.
const ENVELOPE_FPS := 40.0
# Neko-Arc conversion model by Ozzy-Helix:
# https://huggingface.co/Ozzy-Helix/Neko_Arc_Neko_Aruku.RVCv2
# Geralt conversion model by Meronix:
# https://huggingface.co/Meronix/RVC/blob/694d5de5bccfd3bdd0ded4ddbc0cf89238b3e97d/Geralt.zip
const VOICES := [
	{
		&"aim": [
			[
				"Мяу! Щас будет пиздец!",
				preload("res://assets/beaver/voice/neco/aim_1.ogg"),
				"0001999999999885431000000000123559974443388667500007965433358765200111000000000",
			],
			[
				"Лапку сюда… Жопку туда!",
				preload("res://assets/beaver/voice/neco/aim_2.ogg"),
				"00058899998000002973433366653775442000000000000465559970000286112543288653100000000",
			],
			[
				"Ой. Щас будет пыщ!",
				preload("res://assets/beaver/voice/neco/aim_3.ogg"),
				"0000169998865531000000000001345499744458955862000078732222200000000",
			],
		],
		&"own_lost": [
			[
				"Блядь! Это моя любимая!",
				preload("res://assets/beaver/voice/neco/own_lost_1.ogg"),
				"000035487899987640122210000000000499300887889988999977787554677887766555444210000000",
			],
			[
				"Мя?! Она ж на месте сидела!",
				preload("res://assets/beaver/voice/neco/own_lost_2.ogg"),
				"000048888775200000000000499789986331489889996330035222245534887655543100000000",
			],
			[
				"Верни, сука! У неё семья!",
				preload("res://assets/beaver/voice/neco/own_lost_3.ogg"),
				"0000247996768999886420012222887300236431000000000089999888996433445998888887775200000000",
			],
		],
		&"rival_lost": [
			[
				"Опа! Ещё одна под столом!",
				preload("res://assets/beaver/voice/neco/rival_lost_1.ogg"),
				"0000799999200045432100000000146763333389999624798840095012101897578876565420000000",
			],
			[
				"Мя-ха-ха! Минус шашка!",
				preload("res://assets/beaver/voice/neco/rival_lost_2.ogg"),
				"0000578999940000017987510111116643100000004899899998433333459763333101154200000000",
			],
			[
				"Ебать! Улетела за пивом!",
				preload("res://assets/beaver/voice/neco/rival_lost_3.ogg"),
				"00026997657987752001110000000003797775002469999964389500037874465666421000000",
			],
		],
		&"win": [
			[
				"Мя! Я, блядь, чемпион!",
				preload("res://assets/beaver/voice/neco/win_1.ogg"),
				"00026888875200000000004699988889754377999996013211002444999820178887777776654210000000",
			],
		],
		&"lose": [
			[
				"Нет! Мои деревянные дети!",
				preload("res://assets/beaver/voice/neco/lose_1.ogg"),
				"00017888888641000000000000000189999889985458768975799998888888875335898730132133210000000",
			],
		],
		&"draw": [
			[
				"Бля. Кто теперь стол убирает?",
				preload("res://assets/beaver/voice/neco/draw_1.ogg"),
				"000278897897664100000000000000899134630799764220019987897436996988666543000000000000",
			],
		],
	},
	{
		&"aim": [
			[
				"Хм. Дерево против дерева.",
				preload("res://assets/beaver/voice/geralt/aim_1.ogg"),
				"00011339997410000000000024347997997897214688874245544445677846765665310000000",
			],
			[
				"Ну, сука. Посмотрим.",
				preload("res://assets/beaver/voice/geralt/aim_2.ogg"),
				"000036799996566469974133653210000000000000189755249776445354333221000000",
			],
			[
				"Угол хреновый. Сойдёт.",
				preload("res://assets/beaver/voice/geralt/aim_3.ogg"),
				"00004996599973333599989987765544321000000000001456599975467765311100000000",
			],
		],
		&"own_lost": [
			[
				"Блядь. Прощай, шашка.",
				preload("res://assets/beaver/voice/geralt/own_lost_1.ogg"),
				"0001555668998422210000000000000279987678548866654554379997551001222100000000",
			],
			[
				"Хм. Пол сожрал мою шашку.",
				preload("res://assets/beaver/voice/geralt/own_lost_2.ogg"),
				"000012289952100000000000478654449976669987788888664465499865620122322100000000",
			],
			[
				"Сука. Хорошая была шашка.",
				preload("res://assets/beaver/voice/geralt/own_lost_3.ogg"),
				"00002456699973345632100000000000013599999857759877677766765665498865640123321100000000",
			],
		],
		&"rival_lost": [
			[
				"Минус одна. Привет, пол.",
				preload("res://assets/beaver/voice/geralt/rival_lost_1.ogg"),
				"000046799997764436743335554431100000000000004677558999311000167766432100000000",
			],
			[
				"Гори в аду. Под столом.",
				preload("res://assets/beaver/voice/geralt/rival_lost_2.ogg"),
				"0000345999799975689554566543100000000000000159647511699877777554421000000",
			],
			[
				"Улетела. Скатертью, блядь, дорога.",
				preload("res://assets/beaver/voice/geralt/rival_lost_3.ogg"),
				"0001799899742576998765764210000000000100499952685424467765567987432014477868886544543200000000",
			],
		],
		&"win": [
			[
				"Работа сделана. Где, блядь, монеты?",
				preload("res://assets/beaver/voice/geralt/win_1.ogg"),
				"00000659965467642477643246765445555433200000000000000245435799975556599884323676766789973134332100000000",
			],
		],
		&"lose": [
			[
				"Да ну нахуй. Плотину чинить пора.",
				preload("res://assets/beaver/voice/geralt/lose_1.ogg"),
				"000023489999988788998899842214644210000000000000015875313389899952563777665321015887787642100000000",
			],
		],
		&"draw": [
			[
				"Ничья. Дерьмо случается.",
				preload("res://assets/beaver/voice/geralt/draw_1.ogg"),
				"0000688985377538986421000000000000023489789999842368844857988665323442222100000000",
			],
		],
	},
]


var _opponent := 0
var _line_offsets: Array[Dictionary] = [{}, {}]
var _reactions: Array[StringName] = []
var _envelope := ""


func _ready() -> void:
	finished.connect(_on_finished)


func select_opponent(is_blue: bool) -> void:
	_opponent = 1 if is_blue else 0


func speak(cue: StringName) -> void:
	if playing:
		await idle
	_play_line(cue)
	await idle


func react_to_knockout(own_piece: bool) -> void:
	var cue := &"own_lost" if own_piece else &"rival_lost"
	if not playing:
		_play_line(cue)
	elif cue not in _reactions:
		_reactions.append(cue)


func _play_line(cue: StringName) -> void:
	var variants: Array = VOICES[_opponent][cue]
	var offsets := _line_offsets[_opponent]
	var index: int = offsets.get(cue, 0)
	offsets[cue] = (index + 1) % variants.size()
	var line: Array = variants[index]
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


func _on_finished() -> void:
	if not _reactions.is_empty():
		_play_line(_reactions.pop_front())
		return
	subtitle_changed.emit("")
	idle.emit()
