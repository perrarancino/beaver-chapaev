extends AudioStreamPlayer

signal subtitle_changed(text: String)
signal idle

# Each clip stores its normalized loudness as digits sampled at 40 Hz.
const ENVELOPE_FPS := 40.0
const INTRO_LINE := "Дружок, пизда тебе щас будет, если не выиграешь всех бобров!"
# Neko-Arc conversion model by Ozzy-Helix:
# https://huggingface.co/Ozzy-Helix/Neko_Arc_Neko_Aruku.RVCv2
# Geralt conversion model by Meronix:
# https://huggingface.co/Meronix/RVC/blob/694d5de5bccfd3bdd0ded4ddbc0cf89238b3e97d/Geralt.zip
# Chef voice synthesized with Piper Denis (CC0 dataset), with pitch and timing adjusted.
# https://huggingface.co/rhasspy/piper-voices/tree/main/ru/ru_RU/denis/medium
const VOICES := [
	{
		&"intro": [
			[
				INTRO_LINE,
				preload("res://assets/beaver/voice/neco/intro_1.ogg"),
				"00000345879974559998510010000000000000079764389961245589834448995344336864674000000037984311889999667877753557985223233377544359953365875310000000000000",
			],
		],
		&"nose": [
			[
				"Мя! Отпусти нос!",
				preload("res://assets/beaver/voice/neco/nose_1.ogg"),
				"069999998652100000000000004830001896430013788998877752211110000000",
			],
			[
				"Ай! Нос не дёргай!",
				preload("res://assets/beaver/voice/neco/nose_2.ogg"),
				"0478998865310000000000000059898743311899865458999665214655420000000",
			],
		],
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
		&"intro": [
			[
				INTRO_LINE,
				preload("res://assets/beaver/voice/geralt/intro_1.ogg"),
				"00001346667754457663102110000000000015754323785334546665556456543333345433321010000000004689854338999999989999864567777645445543443222257544555544211110000000000",
			],
		],
		&"nose": [
			[
				"Руки прочь от носа.",
				preload("res://assets/beaver/voice/geralt/nose_1.ogg"),
				"355799841125973003789998234458720014565543222222432110000000",
			],
			[
				"Ай. Пусти, сука.",
				preload("res://assets/beaver/voice/geralt/nose_2.ogg"),
				"17999989874320000000002698656531035468853433443486421113432110000000",
			],
		],
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
	{
		&"intro": [
			[
				"Я шеф Бобёр! Сегодня в меню шашки. Твои подам с хрустящей корочкой!",
				preload("res://assets/beaver/voice/chef/intro_1.ogg"),
				"0000026999755688668998655899974211000000000000026887899877888876678877887644489985432224532100000000000000258999854499645898765432227764346886545874358999878543321243210000000000000000",
			],
		],
		&"nose": [
			[
				"Ай! За нос не хватать!",
				preload("res://assets/beaver/voice/chef/nose_1.ogg"),
				"0468998532100000000000000169755774212333116999311685211100000000",
			],
			[
				"Нос шефа не трогать!",
				preload("res://assets/beaver/voice/chef/nose_2.ogg"),
				"037994326752168653564227899535521100000000",
			],
		],
		&"aim": [
			[
				"Так, щепотку соли… и щёлк!",
				preload("res://assets/beaver/voice/chef/aim_1.ogg"),
				"0000004999755321022496448985324775448999888997433258886432210000000000000",
			],
			[
				"Шашечку — на сковородочку!",
				preload("res://assets/beaver/voice/chef/aim_2.ogg"),
				"000001489975676442358766896427889999899856874221256532000000000000000",
			],
			[
				"Сейчас будет фирменный шлепок!",
				preload("res://assets/beaver/voice/chef/aim_3.ogg"),
				"000001487569997556899768953215899887788877764246854437874322100000000000000",
			],
		],
		&"own_lost": [
			[
				"Ай! Это же моя котлетка!",
				preload("res://assets/beaver/voice/chef/own_lost_1.ogg"),
				"0000025899987422100000000000047754698667866899999964358874347887432246421100000000000000",
			],
			[
				"Кто пустил тебя на кухню?!",
				preload("res://assets/beaver/voice/chef/own_lost_2.ogg"),
				"00000049976436875434998643675579977895336885322455421000000000000000",
			],
			[
				"Она ещё сырая была!",
				preload("res://assets/beaver/voice/chef/own_lost_3.ogg"),
				"000000257777899878865568643488889999996456886789864211000000000000000",
			],
		],
		&"rival_lost": [
			[
				"На раздачу! Одна шашка готова!",
				preload("res://assets/beaver/voice/chef/rival_lost_1.ogg"),
				"0000002478999987546999643345421100000000000000029864688996458864325876569975436876656421100000000000000",
			],
			[
				"Хрусть! Приятного аппетита!",
				preload("res://assets/beaver/voice/chef/rival_lost_2.ogg"),
				"000000039999954334210000000000015678899995447767996442466433566534662111000000000000000",
			],
			[
				"Официант! Унесите тарелочку!",
				preload("res://assets/beaver/voice/chef/rival_lost_3.ogg"),
				"0000002687658753378999986542100000000000000146888986468875469644999988899999854421235321000000000000000",
			],
		],
		&"win": [
			[
				"Шеф победил! Счёт за ужин на столе.",
				preload("res://assets/beaver/voice/chef/win_1.ogg"),
				"000000137898444499756886568998753211000000000000025899644789988776678788897421369986676521110000000000000",
			],
		],
		&"lose": [
			[
				"Всё, увольняюсь! Ухожу печь сырники.",
				preload("res://assets/beaver/voice/chef/lose_1.ogg"),
				"000000249999975447877898788899999643210000000000000000368689998668984468876436887766554222342100000000000000000",
			],
		],
		&"draw": [
			[
				"Ничья. Значит, делим последний пирожок!",
				preload("res://assets/beaver/voice/chef/draw_1.ogg"),
				"000002478998544578899863210000000000000000269987446866447899887652599543478985677752178889999545876422210000000000000",
			],
		],
	},
]


var _opponent := 0
var _line_offsets: Dictionary[int, Dictionary] = {}
var _reactions: Array[StringName] = []
var _current_cue: StringName
var _current_line: Array = []
var _interrupted_intro: Array = []
var _intro_resume_at := 0.0
var _next_nose_line := 0


func _ready() -> void:
	finished.connect(_on_finished)


func select_opponent(index: int) -> void:
	_opponent = index


func speak(cue: StringName) -> void:
	if playing:
		await idle
	_play_line(cue)
	await idle


func skip_line() -> void:
	_interrupted_intro = []
	if playing:
		stop()
		_on_finished()


func react_to_knockout(own_piece: bool) -> void:
	var cue := &"own_lost" if own_piece else &"rival_lost"
	if not playing:
		_play_line(cue)
	elif cue not in _reactions:
		_reactions.append(cue)


func react_to_nose_pull() -> void:
	var now := Time.get_ticks_msec()
	if now < _next_nose_line or (playing and _current_cue != &"intro"):
		return
	if playing:
		_interrupted_intro = _current_line
		_intro_resume_at = get_playback_position()
	_next_nose_line = now + 2300
	_play_line(&"nose")


func _play_line(cue: StringName) -> void:
	var variants: Array = VOICES[_opponent][cue]
	var offsets: Dictionary = _line_offsets.get_or_add(_opponent, {})
	var index: int = offsets.get(cue, 0)
	offsets[cue] = (index + 1) % variants.size()
	_play_clip(cue, variants[index])


func _play_clip(cue: StringName, line: Array, from_position := 0.0) -> void:
	_current_cue = cue
	_current_line = line
	stream = line[1]
	play(from_position)
	subtitle_changed.emit(line[0])


func mouth_opening() -> float:
	if not playing:
		return 0.0
	var envelope: String = _current_line[2]
	var frame := maxf(0.0, get_playback_position() * ENVELOPE_FPS)
	var first := mini(int(frame), envelope.length() - 1)
	var next := mini(first + 1, envelope.length() - 1)
	return lerpf(envelope.unicode_at(first) - 48, envelope.unicode_at(next) - 48,
		fposmod(frame, 1.0)) / 9.0


func _on_finished() -> void:
	if not _interrupted_intro.is_empty():
		var line := _interrupted_intro
		_interrupted_intro = []
		_play_clip(&"intro", line, _intro_resume_at)
		return
	if not _reactions.is_empty():
		_play_line(_reactions.pop_front())
		return
	_current_cue = &""
	subtitle_changed.emit("")
	idle.emit()
