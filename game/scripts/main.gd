extends Node2D
## 沙威瑪斬 —— 偽 3D 旋轉沙威瑪 + 2D 動作
##
## 一關 = 一串沙威瑪排隊上場，最後是巨無霸 BOSS。
## 每根沙威瑪：砍光肉 → 沙威核露出 → 打爆 → 下一根滑進來。
## 沙威瑪用「攤平的肉貼圖」貼在一條條直條上，轉起來就是真的在轉。

const DrawerScript := preload("res://scripts/drawer.gd")
const ShawarmaScript := preload("res://scripts/shawarma.gd")

const W := 960.0
const H := 540.0
const CX := 480.0
const FLOOR_Y := 476.0
const CYL_BOT := 452.0
const NCOL := Shawarma.NCOL
const STEP := Shawarma.STEP
const ROW_H := Shawarma.ROW_H
const ZONE := 70.0        # 主角能自由走動的範圍，超過就繞著沙威瑪轉
const P_HP_MAX := 20.0
const SLASH_DMG := 22.0
const ATTACK_T := 0.2

const STAGES := [
	{"name": "夜市第一攤", "diff": 1.0, "queue": ["chicken", "chicken", "beef", "chicken", "beef", "boss"]},
	{"name": "辣味大街", "diff": 1.2, "queue": ["chicken", "spicy", "beef", "spicy", "chicken", "beef", "spicy", "boss"]},
	{"name": "沙威瑪工廠", "diff": 1.4, "queue": ["beef", "spicy", "beef", "chicken", "spicy", "beef", "spicy", "beef", "boss"]},
]

## 開場故事 (圖片放 assets/story/story_1.png ~ story_4.png；沒有圖時用遊戲畫面代替)
const STORY := [
	"深夜的夜市，沙威瑪攤的烤爐突然發出奇怪的光……",
	"烤肉柱裡的「沙威核」甦醒了！肉一直長、一直長，整條夜市快被沙威瑪淹沒了！",
	"就在這時，吃貨柯基英雄——奇異果，穿上紅色戰甲、拔出光劍！",
	"「砍得比長得快就對了！」　沙威瑪斬，開始！",
]

const ANIM_FALLBACK := {
	"run": "idle", "fall": "jump", "jump": "idle", "slash2": "slash1", "slash3": "slash1", "slash1": "idle",
	"upslash": "jump", "hurt": "idle", "win": "idle", "dash": "run", "die": "idle",
}

var font: Font
var anims := {}           # action -> {"frames": [{tex, ax, ay}], "fps"}
var meat_tex: Texture2D
var raw_tex: Texture2D
var core_tex: Texture2D
var sfx := {}
var bgm: AudioStreamPlayer

var world: Node2D
var bg_layer: Node2D
var shaw_layer: Node2D
var glow_layer: Node2D
var fx_back: Node2D
var fx_front: Node2D
var fx_add: Node2D
var hud: Node2D
var player_spr: Sprite2D

var state := "title"      # title / story / play / clear / gameover / ending
var story_i := 0
var story_chars := 0.0
var story_imgs: Array = []
var stage := 0
var t := 0.0
var state_t := 0.0
var stage_time := 0.0
var total_time := 0.0
var hitstop := 0.0
var tap := false

var shaw: Shawarma = null
var shaw_idx := 0
var shaw_state := "arrive"  # arrive / fight / explode
var shaw_t := 0.0
var phi := 0.0

var score := 0
var combo := 0
var combo_t := 0.0
var best_combo := 0

var p_pos := Vector2(CX, FLOOR_Y)
var p_vel := Vector2.ZERO
var p_face := 1
var p_floor := true
var p_jumps := 1
var p_hp := P_HP_MAX
var p_attack_t := 0.0
var p_attack_cd := 0.0
var p_combo := 0
var p_combo_t := 0.0
var p_up_slash := false
var p_dash_t := 0.0
var p_dash_cd := 0.0
var p_hurt_t := 0.0
var p_inv_t := 0.0
var anim_key := ""
var anim_t := 0.0
var ghost_t := 0.0

var drops: Array = []
var waves: Array = []
var wave_t := 0.0
var particles: Array = []
var ghosts: Array = []
var arcs: Array = []
var popups: Array = []
var grease_t := 2.0
var steam_t := 0.0
var shake := 0.0
var flash_screen := 0.0
var banner := ""
var banner_sub := ""
var banner_t := 0.0
var sfx_cd := {}
var buildings: Array = []

var autoplay := false   # 測試用：--autoplay 或網址 ?autoplay 讓電腦自己玩
var bot_t := 0.0
var log_t := 0.0


# ==================================================================
# 初始化
# ==================================================================
func _ready() -> void:
	randomize()
	_setup_input()
	font = load("res://assets/font.ttf")
	_load_art()
	for n in ["slash", "hit", "jump", "hurt", "boom", "core", "splat", "dash"]:
		sfx[n] = load("res://assets/sfx_%s.wav" % n)

	world = Node2D.new()
	add_child(world)
	bg_layer = _make_drawer(world, _draw_bg)
	shaw_layer = _make_drawer(world, _draw_shawarma)
	glow_layer = _make_drawer(world, _draw_glow)
	glow_layer.material = _add_material()
	fx_back = _make_drawer(world, _draw_fx_back)
	player_spr = Sprite2D.new()
	player_spr.centered = false
	player_spr.scale = Vector2(0.5, 0.5)
	world.add_child(player_spr)
	fx_front = _make_drawer(world, _draw_fx_front)
	fx_add = _make_drawer(world, _draw_fx_add)
	fx_add.material = _add_material()

	var hud_cl := CanvasLayer.new()
	hud_cl.layer = 5
	add_child(hud_cl)
	hud = _make_drawer(hud_cl, _draw_hud)
	_setup_touch()

	bgm = AudioStreamPlayer.new()
	bgm.stream = load("res://assets/bgm.wav")
	bgm.volume_db = -9.0
	add_child(bgm)
	bgm.finished.connect(bgm.play)

	for i in 26:
		buildings.append({"x": i * 74.0 + randf_range(-10, 10), "w": randf_range(50, 80), "h": randf_range(90, 240), "s": randi()})

	autoplay = "--autoplay" in OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		autoplay = autoplay or (q is String and "autoplay" in q)
	_to_title()


func _load_art() -> void:
	meat_tex = load("res://assets/shawarma/meat_surface.png")
	raw_tex = load("res://assets/shawarma/meat_raw.png")
	core_tex = load("res://assets/shawarma/core.png")
	for i in STORY.size():
		var path := "res://assets/story/story_%d.png" % (i + 1)
		story_imgs.append(load(path) if ResourceLoader.exists(path) else null)
	var f := FileAccess.open("res://assets/art.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	var hero: Dictionary = data["hero"]
	for action in hero:
		var a: Dictionary = hero[action]
		var frames: Array = []
		for fr in a["frames"]:
			frames.append({"tex": load("res://assets/" + String(fr["file"])), "ax": float(fr["ax"]), "ay": float(fr["ay"])})
		anims[action] = {"frames": frames, "fps": float(a["fps"])}


func _add_material() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


func _make_drawer(parent: Node, f: Callable) -> Node2D:
	var d: Node2D = DrawerScript.new()
	d.fn = f
	parent.add_child(d)
	return d


func _setup_input() -> void:
	_bind("move_left", [KEY_LEFT, KEY_A], [JOY_BUTTON_DPAD_LEFT])
	_bind("move_right", [KEY_RIGHT, KEY_D], [JOY_BUTTON_DPAD_RIGHT])
	_bind("up", [KEY_UP, KEY_W], [JOY_BUTTON_DPAD_UP])
	_bind("jump", [KEY_Z, KEY_SPACE, KEY_K], [JOY_BUTTON_A])
	_bind("attack", [KEY_X, KEY_J], [JOY_BUTTON_X])
	_bind("dash", [KEY_C, KEY_L, KEY_SHIFT], [JOY_BUTTON_B, JOY_BUTTON_RIGHT_SHOULDER])
	_bind("start", [KEY_ENTER, KEY_KP_ENTER], [JOY_BUTTON_START])


func _bind(action: String, keys: Array, joys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in joys:
		var j := InputEventJoypadButton.new()
		j.button_index = b
		InputMap.action_add_event(action, j)


func _setup_touch() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var defs := [
		["left", "move_left", Vector2(14, 424)],
		["right", "move_right", Vector2(124, 424)],
		["up", "up", Vector2(69, 330)],
		["attack", "attack", Vector2(728, 424)],
		["jump", "jump", Vector2(838, 424)],
		["dash", "dash", Vector2(838, 316)],
	]
	for d in defs:
		var b := TouchScreenButton.new()
		b.texture_normal = load("res://assets/btn_%s.png" % d[0])
		b.action = d[1]
		b.position = d[2]
		b.scale = Vector2(0.8, 0.8)
		b.passby_press = true
		b.visibility_mode = TouchScreenButton.VISIBILITY_TOUCHSCREEN_ONLY
		layer.add_child(b)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		tap = true
	elif event is InputEventMouseButton and event.pressed:
		tap = true


# ==================================================================
# 流程
# ==================================================================
func _to_title() -> void:
	state = "title"
	state_t = 0.0
	shaw = ShawarmaScript.new()
	shaw.setup("beef", 1.0)
	shaw.cx = CX + 120.0
	shaw.spin_speed = 0.6
	phi = 0.0
	p_pos = Vector2(CX - 250, FLOOR_Y)
	p_face = 1
	p_vel = Vector2.ZERO


func _start_game() -> void:
	stage = 0
	total_time = 0.0
	score = 0
	best_combo = 0
	if not bgm.playing:
		bgm.play()
	_start_stage(0)


func _start_stage(s: int) -> void:
	stage = s
	state = "play"
	state_t = 0.0
	stage_time = 0.0
	drops.clear()
	waves.clear()
	p_pos = Vector2(CX - 40, FLOOR_Y)
	p_vel = Vector2.ZERO
	p_hp = P_HP_MAX
	p_inv_t = 0.0
	p_hurt_t = 0.0
	grease_t = 3.0
	combo = 0
	_spawn_shawarma(0)
	_banner("STAGE %d" % (s + 1), String(STAGES[s]["name"]) + "　共 %d 根沙威瑪" % STAGES[s]["queue"].size(), 2.2)


func _spawn_shawarma(i: int) -> void:
	shaw_idx = i
	var q: Array = STAGES[stage]["queue"]
	shaw = ShawarmaScript.new()
	shaw.setup(String(q[i]), float(STAGES[stage]["diff"]))
	shaw.cx = CX + 720.0
	shaw_state = "arrive"
	shaw_t = 0.0
	waves.clear()
	if shaw.is_boss:
		_banner("BOSS!", shaw.title, 2.0)
		shake = 6.0


func _banner(a: String, b: String = "", d: float = 2.0) -> void:
	banner = a
	banner_sub = b
	banner_t = d


func _play(n: String, vol := 0.0, pitch := 1.0, cd := 0.0) -> void:
	if cd > 0.0:
		if float(sfx_cd.get(n, 0.0)) > t:
			return
		sfx_cd[n] = t + cd
	var p := AudioStreamPlayer.new()
	p.stream = sfx[n]
	p.volume_db = vol
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# ==================================================================
# 主迴圈
# ==================================================================
func _process(delta: float) -> void:
	var dt := minf(delta, 1.0 / 30.0)
	t += dt
	banner_t -= dt
	flash_screen -= dt
	if autoplay:
		_bot(dt)
	var confirm := Input.is_action_just_pressed("start") or Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("jump") or tap
	tap = false

	if hitstop > 0.0:
		hitstop -= dt
	else:
		state_t += dt
		match state:
			"title":
				shaw.update(dt)
				shaw.events.clear()
				_meat_fx(dt)
				if confirm:
					story_i = 0
					story_chars = 0.0
					state = "story"
					state_t = 0.0
					if not bgm.playing:
						bgm.play()
			"story":
				shaw.update(dt)
				shaw.events.clear()
				_meat_fx(dt)
				shaw.core_phase = story_i == 1
				story_chars += dt * 26.0
				var txt: String = STORY[story_i]
				if Input.is_action_just_pressed("dash"):
					shaw.core_phase = false
					_start_game()
				elif confirm and state_t > 0.2:
					if story_chars < txt.length():
						story_chars = txt.length()
					else:
						story_i += 1
						story_chars = 0.0
						state_t = 0.0
						if story_i >= STORY.size():
							shaw.core_phase = false
							_start_game()
			"play":
				stage_time += dt
				_update_play(dt)
			"clear":
				_update_player(dt)
				if state_t > 3.8:
					if stage < STAGES.size() - 1:
						_start_stage(stage + 1)
					else:
						state = "ending"
						state_t = 0.0
			"gameover":
				if shaw:
					shaw.update(dt)
					shaw.events.clear()
				p_vel.y += 1500.0 * dt
				p_pos.y = minf(FLOOR_Y, p_pos.y + p_vel.y * dt)
				if state_t > 1.2 and confirm:
					score = int(score * 0.5)
					_start_stage(stage)
			"ending":
				if state_t > 2.0 and confirm:
					_to_title()
		_update_fx(dt)

	shake = maxf(0.0, shake - dt * 30.0)
	world.position = Vector2(randf_range(-shake, shake), randf_range(-shake, shake)) if shake > 0.0 else Vector2.ZERO
	_update_player_sprite(dt)
	for n in [bg_layer, shaw_layer, glow_layer, fx_back, fx_front, fx_add, hud]:
		n.queue_redraw()


func _update_play(dt: float) -> void:
	_update_player(dt)
	combo_t -= dt
	if combo_t <= 0.0:
		combo = 0
	shaw_t += dt

	match shaw_state:
		"arrive":
			# 沙威瑪從右邊沿著烤爐軌道滑進來
			var k := clampf(shaw_t / 0.8, 0.0, 1.0)
			shaw.cx = CX + 720.0 * pow(1.0 - k, 3.0)
			shaw.update(dt)
			shaw.events.clear()
			if k >= 1.0:
				shaw_state = "fight"
				shaw_t = 0.0
				shake = 3.0
				_play("splat", -6.0, 0.5)
		"fight":
			shaw.update(dt)
			_handle_events()
			_meat_fx(dt)
			if not shaw.core_phase:
				if shaw.ratio() < 0.06:
					_burn_scraps()
					_enter_core()
			else:
				shaw.core_t -= dt
				if shaw.is_boss:
					wave_t -= dt
					if wave_t <= 0.0:
						wave_t = 2.4 - stage * 0.3
						waves.append({"x": CX - shaw.r_core, "dir": -1.0})
						waves.append({"x": CX + shaw.r_core, "dir": 1.0})
						_play("splat", -4.0, 0.6)
				if shaw.core_t <= 0.0:
					shaw.core_phase = false
					waves.clear()
					for i in shaw.meat.size():
						shaw.meat[i] = 30.0
						shaw.fresh[i] = 1.0
						shaw.bulge[i] = 1.0
					_banner("肉又長回來了！", "", 1.4)
					shake = 6.0
					_play("splat", 0.0, 0.7)
		"explode":
			if shaw_t > 1.0:
				if shaw_idx + 1 < STAGES[stage]["queue"].size():
					_spawn_shawarma(shaw_idx + 1)
				else:
					_stage_clear()
				return

	# 震波
	for w in waves:
		w["x"] += float(w["dir"]) * 330.0 * dt
		if p_pos.y > FLOOR_Y - 24.0 and absf(float(w["x"]) - p_pos.x) < 20.0:
			_hurt(3.0, float(w["x"]) - float(w["dir"]) * 10.0)
	waves = waves.filter(func(w): return float(w["x"]) > -40.0 and float(w["x"]) < W + 40.0)

	# 熱油滴
	if shaw_state == "fight":
		grease_t -= dt
		if grease_t <= 0.0:
			grease_t = shaw.grease * randf_range(0.7, 1.3)
			drops.append({"x": shaw.cx + randf_range(-0.8, 0.8) * shaw.r_max, "y": shaw.top - 4.0, "vy": 0.0, "warn": 0.7})
	for d in drops:
		if float(d["warn"]) > 0.0:
			d["warn"] = float(d["warn"]) - dt
			continue
		d["vy"] = float(d["vy"]) + 900.0 * dt
		d["y"] = float(d["y"]) + float(d["vy"]) * dt
		var dp := Vector2(float(d["x"]), float(d["y"]))
		if dp.distance_to(p_pos + Vector2(0, -50)) < 30.0:
			_hurt(2.0, dp.x)
			d["dead"] = true
		elif dp.y >= FLOOR_Y:
			d["dead"] = true
			for k in 6:
				_particle("juice", Vector2(dp.x, FLOOR_Y), Vector2(randf_range(-120, 120), randf_range(-200, -60)), Color(1.0, 0.75, 0.2), 3.0, 0.4)
			_play("splat", -12.0, randf_range(0.9, 1.2), 0.1)
	drops = drops.filter(func(d): return not d.has("dead"))


func _burn_scraps() -> void:
	# 剩下的碎肉直接烤焦掉，不用滿場找小肉芽
	for c in NCOL:
		for r in shaw.nrow:
			var i := c * shaw.nrow + r
			if shaw.meat[i] > 0.0:
				shaw.meat[i] = 0.0
				var a := shaw.col_angle(c, phi) + STEP * 0.5
				if cos(a) > 0.0:
					for k in 3:
						_particle("smoke", shaw.pp(shaw.r_core + 10.0, a, shaw.row_y(r) + ROW_H * 0.5), Vector2(randf_range(-30, 30), randf_range(-90, -40)), Color(0.25, 0.2, 0.18, 0.6), 8.0, 0.9)


func _enter_core() -> void:
	shaw.core_phase = true
	shaw.core_t = shaw.core_time_max
	shaw.core_hp = shaw.core_hp_max
	wave_t = 1.6
	shake = 6.0
	_banner("沙威核 露出！", "", 1.0)
	_play("core", 0.0, 0.7)


func _shawarma_destroyed() -> void:
	shaw.core_phase = false
	shaw_state = "explode"
	shaw_t = 0.0
	waves.clear()
	shake = 12.0 if shaw.is_boss else 8.0
	hitstop = 0.2 if shaw.is_boss else 0.08
	flash_screen = 0.15
	_play("boom", 0.0 if shaw.is_boss else -4.0, 1.0 if shaw.is_boss else 1.3)
	var c := Vector2(shaw.cx, (shaw.top + shaw.bot) * 0.5)
	var n := 90 if shaw.is_boss else 45
	for k in n:
		var a := randf() * TAU
		var sp := randf_range(100, 560)
		var v := Vector2(cos(a), sin(a)) * sp + Vector2(0, -150)
		var p := c + Vector2(randf_range(-30, 30), randf_range(-(shaw.bot - shaw.top) * 0.4, (shaw.bot - shaw.top) * 0.4))
		match k % 3:
			0: _particle("spark", p, v, Color(1.0, randf_range(0.5, 0.9), 0.2), 4.0, randf_range(0.4, 0.9))
			1: _particle("chunk", p, v, Color.WHITE, randf_range(10, 18), randf_range(0.8, 1.4))
			_: _particle("juice", p, v, Color(0.95, 0.65, 0.2), randf_range(3, 6), randf_range(0.6, 1.0))
	# 速度獎勵 + 回血 (吃一口沙威瑪)
	var par := 25.0 if shaw.is_boss else 9.0
	var bonus := int(maxf(0.0, par - shaw.life_t) * 100.0) + (3000 if shaw.is_boss else 500)
	score += bonus
	p_hp = minf(P_HP_MAX, p_hp + (8.0 if shaw.is_boss else 3.0))
	var msg := "斬殺！ +%d" % bonus
	if shaw.life_t < par * 0.6:
		msg = "神速斬殺！ +%d" % bonus
	_popup(msg, Vector2(shaw.cx, shaw.top - 20), Color(1, 0.9, 0.3), 26)
	_popup("HP +%d" % (8 if shaw.is_boss else 3), p_pos + Vector2(0, -130), Color(0.5, 1, 0.6), 18)


func _stage_clear() -> void:
	state = "clear"
	state_t = 0.0
	total_time += stage_time
	shaw = null
	_banner("STAGE CLEAR!", "時間 %s　最高連擊 %d" % [_fmt_time(stage_time), best_combo], 3.6)


func _hurt(dmg: float, from_x: float) -> void:
	if p_inv_t > 0.0 or state != "play":
		return
	p_hp -= dmg
	p_inv_t = 1.1
	p_hurt_t = 0.3
	combo = 0
	var dir := 1.0 if p_pos.x >= from_x else -1.0
	p_vel = Vector2(dir * 260.0, -260.0)
	p_floor = false
	shake = 6.0
	_play("hurt")
	if p_hp <= 0.0:
		p_hp = 0.0
		state = "gameover"
		state_t = 0.0
		p_attack_t = 0.0
		p_dash_t = 0.0
		_play("boom", -4.0, 1.3)


# ------------------------------------------------------------------
# 主角
# ------------------------------------------------------------------
func _update_player(dt: float) -> void:
	p_attack_cd -= dt
	p_attack_t -= dt
	p_combo_t -= dt
	p_dash_cd -= dt
	p_inv_t -= dt
	p_hurt_t -= dt
	var control := p_hurt_t <= 0.0
	var dir := 0.0
	if control:
		dir = Input.get_axis("move_left", "move_right")
	if dir != 0.0 and p_attack_t <= 0.0:
		p_face = 1 if dir > 0.0 else -1

	if control and Input.is_action_just_pressed("dash") and p_dash_cd <= 0.0:
		p_dash_t = 0.26
		p_dash_cd = 0.42
		_play("dash", -6.0)

	if p_hurt_t > 0.0:
		p_vel.x = move_toward(p_vel.x, 0.0, 900.0 * dt)
	elif p_dash_t > 0.0:
		p_dash_t -= dt
		p_vel.x = p_face * 540.0
		ghost_t -= dt
		if ghost_t <= 0.0:
			ghost_t = 0.04
			var fr := _anim_frame()
			ghosts.append({"p": p_pos, "fr": fr, "f": p_face, "life": 0.25})
	else:
		p_vel.x = dir * 235.0

	if control and Input.is_action_just_pressed("jump"):
		if p_floor:
			p_vel.y = -610.0
			p_floor = false
			p_jumps = 1
			_play("jump", -4.0)
		elif p_jumps > 0:
			p_vel.y = -540.0
			p_jumps -= 1
			_play("jump", -4.0, 1.3)
			for k in 8:
				var a := TAU * k / 8.0
				_particle("spark", p_pos, Vector2(cos(a) * 140, sin(a) * 40), Color(0.5, 1.0, 0.6), 3.0, 0.25)
	if Input.is_action_just_released("jump") and p_vel.y < -220.0:
		p_vel.y *= 0.5

	p_vel.y += 1500.0 * dt
	p_pos.y += p_vel.y * dt
	if p_pos.y >= FLOOR_Y:
		p_pos.y = FLOOR_Y
		p_vel.y = 0.0
		p_floor = true
		p_jumps = 1
	else:
		p_floor = false

	# 走到邊緣 → 視角繞著沙威瑪轉
	var nx := p_pos.x + p_vel.x * dt
	var lo := CX - ZONE
	var hi := CX + ZONE
	var orbit_r := shaw.r_max if shaw else 120.0
	if nx > hi:
		phi += (nx - hi) / orbit_r
		nx = hi
	elif nx < lo:
		phi -= (lo - nx) / orbit_r
		nx = lo
	p_pos.x = nx

	if control and state == "play":
		if (Input.is_action_just_pressed("attack") and p_attack_cd <= 0.0) or (Input.is_action_pressed("attack") and p_attack_cd <= -0.05):
			_do_attack()


func _do_attack() -> void:
	p_combo = (p_combo % 3) + 1 if p_combo_t > 0.0 else 1
	p_combo_t = 0.5
	p_attack_t = ATTACK_T
	p_attack_cd = 0.14
	p_up_slash = Input.is_action_pressed("up")
	var big := p_combo == 3
	var rect: Rect2
	var f := float(p_face)
	var mid := p_pos + Vector2(f * 30.0, -75.0)
	if p_up_slash:
		# 升龍斬：從身體前下方往頭上劃一大圈
		rect = Rect2(p_pos.x - 70, p_pos.y - 280, 140, 240)
		_slash_fx(p_pos + Vector2(f * 10.0, -130.0), 95.0, PI * 0.9 if p_face > 0 else PI * 0.1, PI * 1.2 * f, 26.0, 0.22)
	elif not p_floor:
		# 空中斬：範圍往上延伸，跳起來就砍得到上面的肉
		var w := 170.0 if big else 140.0
		var x0 := p_pos.x - 25.0 if p_face > 0 else p_pos.x + 25.0 - w
		rect = Rect2(x0, p_pos.y - 225.0, w, 235.0)
		_slash_fx(mid + Vector2(f * 5.0, -25.0), 110.0 if big else 95.0, -PI * 0.5 - f * 0.9 if p_face > 0 else -PI * 0.5 + 0.9, 3.4 * f, 30.0 if big else 24.0, 0.2)
	elif big:
		# 第 3 段：迴旋大斬
		rect = Rect2(p_pos.x - 150.0, p_pos.y - 190.0, 300.0, 195.0)
		_slash_fx(p_pos + Vector2(0, -80.0), 115.0, -PI * 0.5, TAU * 0.95 * f, 34.0, 0.26)
		flash_screen = maxf(flash_screen, 0.05)
	else:
		var w := 135.0
		var x0 := p_pos.x - 20.0 if p_face > 0 else p_pos.x + 20.0 - w
		rect = Rect2(x0, p_pos.y - 158.0, w, 160.0)
		if p_combo == 1:
			# 第 1 段：由上往下斜劈
			_slash_fx(mid, 88.0, -PI * 0.5 - 0.5 * f if p_face > 0 else -PI * 0.5 + 0.5, 2.9 * f, 24.0, 0.18)
		else:
			# 第 2 段：由下往上反手掃
			_slash_fx(mid + Vector2(0, -6), 84.0, PI * 0.5 + 0.2 if p_face > 0 else PI * 0.5 - 0.2, -2.9 * f, 22.0, 0.18)
	_play("slash", -6.0, 0.85 if big else randf_range(1.0, 1.2))
	if shaw == null or shaw_state != "fight":
		return
	var dmg := SLASH_DMG * (1.8 if big else 1.0)
	var hits: Array = shaw.hit(rect, dmg, phi)
	var removed := 0.0
	var n_imp := 0
	for h in hits:
		var cc: Vector2 = h[0]
		removed += float(h[1])
		if n_imp < 3:
			n_imp += 1
			_particle("impact", cc + Vector2(randf_range(-8, 8), randf_range(-8, 8)), Vector2.ZERO, Color.WHITE, 26.0 if big else 18.0, 0.16)
		# 肉汁噴出 + 肉塊飛出
		for k in 2:
			_particle("juice", cc, Vector2(randf_range(-90, 90) + p_face * 120.0, randf_range(-300, -60)), Color(0.78, 0.45, 0.1, 0.9), randf_range(2.0, 3.5), randf_range(0.4, 0.7))
		if randf() < 0.7:
			_particle("chunk", cc, Vector2(randf_range(-60, 60) + p_face * 180.0, randf_range(-320, -120)), Color.WHITE, randf_range(9, 15), randf_range(0.7, 1.1))
	if hits.size() > 0:
		combo += 1
		combo_t = 1.2
		best_combo = maxi(best_combo, combo)
		score += int(removed * (1.0 + combo / 20.0))
		hitstop = 0.045 if big else 0.025
		shake = maxf(shake, 5.0 if big else 2.5)
		_play("hit", -2.0, randf_range(0.85, 1.15), 0.05)
	if shaw.core_phase and rect.intersects(shaw.core_rect()):
		shaw.core_hp -= 2 if big else 1
		shaw.core_flash = 0.1
		hitstop = 0.05
		shake = 5.0
		combo += 1
		combo_t = 1.2
		_play("core", -2.0, randf_range(0.9, 1.1))
		var hp := rect.intersection(shaw.core_rect()).get_center()
		_particle("impact", hp, Vector2.ZERO, Color.WHITE, 34.0, 0.2)
		for k in 10:
			_particle("spark", hp, Vector2(randf_range(-260, 260), randf_range(-260, 100)), Color(1, 0.9, 0.4), 3.0, 0.35)
		if shaw.core_hp <= 0:
			_shawarma_destroyed()


# ------------------------------------------------------------------
# 特效
# ------------------------------------------------------------------
func _particle(kind: String, p: Vector2, v: Vector2, col: Color, size: float, life: float) -> void:
	if particles.size() > 500:
		return
	var d := {"k": kind, "p": p, "v": v, "c": col, "s": size, "life": life, "max": life, "rot": randf() * TAU, "vr": randf_range(-10, 10)}
	if kind == "chunk":
		d["reg"] = Rect2(randf_range(0, 980), randf_range(0, 360), randf_range(28, 44), randf_range(22, 34))
	particles.append(d)


func _popup(s: String, p: Vector2, col: Color, size: int) -> void:
	popups.append({"s": s, "p": p, "c": col, "size": size, "life": 1.2})


## 肉汁甩出、蒸氣、往下滴
func _meat_fx(dt: float) -> void:
	if shaw == null:
		return
	# 旋轉時從兩側邊緣甩出肉汁
	var rate := absf(shaw.spin_speed) * shaw.ratio() * (40.0 if shaw.is_boss else 26.0)
	var n := int(rate * dt + randf())
	for k in n:
		var side := -1.0 if randf() < 0.5 else 1.0
		var r := randi() % shaw.nrow
		var c := int(round((side * PI * 0.5 - shaw.spin + phi) / STEP)) % NCOL
		c = (c + NCOL) % NCOL
		var i := c * shaw.nrow + r
		if shaw.meat[i] < 15.0:
			continue
		var y := shaw.row_y(r) + randf() * ROW_H
		var p := Vector2(shaw.cx + side * shaw.radius(shaw.meat[i], r), y)
		_particle("juice", p, Vector2(side * randf_range(60, 200), randf_range(-150, 10)), Color(0.8, 0.48, 0.12, 0.85), randf_range(1.6, 2.8), randf_range(0.4, 0.8))
	# 蒸氣
	steam_t -= dt
	if steam_t <= 0.0:
		steam_t = 0.09
		_particle("steam", Vector2(shaw.cx + randf_range(-0.7, 0.7) * shaw.r_max, shaw.top), Vector2(randf_range(-10, 10), randf_range(-45, -25)), Color(1, 1, 1, 0.1), randf_range(8, 14), randf_range(1.2, 1.8))


func _handle_events() -> void:
	for e in shaw.events:
		var c: int = e[1]
		var r: int = e[2]
		var a := shaw.col_angle(c, phi) + STEP * 0.5
		if cos(a) < 0.1:
			continue
		var p := shaw.pp(shaw.radius(shaw.meat[c * shaw.nrow + r], r), a, shaw.row_y(r) + ROW_H * 0.5)
		match String(e[0]):
			"sprout":
				# 肉芽冒出來：噗滋
				for k in 6:
					_particle("pink", p, Vector2(randf_range(-80, 80), randf_range(-160, -40)), Color(1.0, 0.55, 0.55), 3.0, 0.4)
				_play("splat", -16.0, 1.7, 0.12)
			"swell":
				for k in 2:
					_particle("juice", p + Vector2(randf_range(-8, 8), 0), Vector2(randf_range(-30, 30), randf_range(-60, 0)), Color(0.95, 0.6, 0.18), 2.5, 0.5)
			"drip":
				var bp := Vector2(p.x, shaw.bot + 4)
				for k in 3:
					_particle("juice", bp, Vector2(randf_range(-50, 50), randf_range(-90, -30)), Color(0.9, 0.6, 0.18), 2.0, 0.3)
	shaw.events.clear()


func _update_fx(dt: float) -> void:
	for p in particles:
		var k: String = p["k"]
		var g := 900.0
		if k == "steam" or k == "smoke":
			g = -30.0
			p["s"] = float(p["s"]) + dt * 18.0
		elif k == "chunk":
			g = 1000.0
		elif k == "impact":
			g = 0.0
		p["v"] = Vector2(p["v"]) + Vector2(0, g * dt)
		p["p"] = Vector2(p["p"]) + Vector2(p["v"]) * dt
		p["rot"] = float(p["rot"]) + float(p["vr"]) * dt
		p["life"] = float(p["life"]) - dt
		if Vector2(p["p"]).y > FLOOR_Y + 6.0 and g > 0.0:
			p["p"] = Vector2(Vector2(p["p"]).x, FLOOR_Y + 6.0)
			p["v"] = Vector2(Vector2(p["v"]).x * 0.4, -Vector2(p["v"]).y * 0.25)
			p["vr"] = float(p["vr"]) * 0.5
	particles = particles.filter(func(p): return float(p["life"]) > 0.0)
	for g in ghosts:
		g["life"] = float(g["life"]) - dt
	ghosts = ghosts.filter(func(g): return float(g["life"]) > 0.0)
	for a in arcs:
		a["life"] = float(a["life"]) - dt
	arcs = arcs.filter(func(a): return float(a["life"]) > 0.0)
	for p in popups:
		p["life"] = float(p["life"]) - dt
		p["p"] = Vector2(p["p"]) + Vector2(0, -40.0 * dt)
	popups = popups.filter(func(p): return float(p["life"]) > 0.0)


# ------------------------------------------------------------------
# 主角動畫
# ------------------------------------------------------------------
func _resolve_anim(key: String) -> String:
	var k := key
	for n in 6:
		if anims.has(k):
			return k
		k = String(ANIM_FALLBACK.get(k, "idle"))
	return "idle"


func _player_action() -> String:
	if state == "gameover":
		return "die"
	if p_hurt_t > 0.0:
		return "hurt"
	if p_attack_t > 0.0:
		return "upslash" if p_up_slash else "slash%d" % maxi(1, p_combo)
	if p_dash_t > 0.0:
		return "dash"
	if not p_floor:
		return "jump" if p_vel.y < 0.0 else "fall"
	if state == "clear" or state == "ending":
		return "win"
	if absf(p_vel.x) > 1.0:
		return "run"
	return "idle"


func _anim_frame() -> Dictionary:
	var want := _player_action()
	var key := _resolve_anim(want)
	var a: Dictionary = anims[key]
	var frames: Array = a["frames"]
	var n := frames.size()
	var idx := 0
	if want.begins_with("slash") or want == "upslash":
		idx = mini(n - 1, int((1.0 - p_attack_t / ATTACK_T) * n))
	elif want == "die":
		idx = mini(n - 1, int(anim_t * float(a["fps"])))
	else:
		idx = int(anim_t * float(a["fps"])) % n
	return frames[clampi(idx, 0, n - 1)]


func _update_player_sprite(dt: float) -> void:
	var want := _player_action()
	if want != anim_key:
		anim_key = want
		anim_t = 0.0
	anim_t += dt
	var fr := _anim_frame()
	var tx: Texture2D = fr["tex"]
	player_spr.texture = tx
	player_spr.flip_h = p_face < 0
	var ax := float(fr["ax"]) if p_face > 0 else 1.0 - float(fr["ax"])
	player_spr.offset = Vector2(-ax * tx.get_width(), -float(fr["ay"]) * tx.get_height())
	player_spr.position = p_pos
	# 沒有跑步圖時用彈跳代替
	if want == "run" and not anims.has("run"):
		player_spr.position.y -= absf(sin(t * 14.0)) * 4.0
	var blink := p_inv_t > 0.0 and int(t * 20.0) % 2 == 0 and state == "play"
	player_spr.modulate = Color(1, 0.55, 0.55) if p_hurt_t > 0.0 else Color(1, 1, 1, 0.35 if blink else 1.0)


# ==================================================================
# 繪圖工具
# ==================================================================
func _quad(ci: CanvasItem, pts: Array, col: Color) -> void:
	ci.draw_primitive(PackedVector2Array(pts), PackedColorArray([col, col, col, col]), PackedVector2Array())


const QUAD_IDX := [0, 1, 2, 0, 2, 3]


## 上下兩種顏色的貼圖四邊形 (做出每片肉上亮下暗)
func _quad_tex2(ci: CanvasItem, pts: Array, ct: Color, cb: Color, u0: float, u1: float, v0: float, v1: float, tex: Texture2D) -> void:
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), PackedInt32Array(QUAD_IDX), PackedVector2Array(pts),
		PackedColorArray([ct, ct, cb, cb]), PackedVector2Array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]),
		PackedInt32Array(), PackedFloat32Array(), tex.get_rid())


## 貼圖四邊形。注意：draw_primitive 在 Godot 4.3 連續呼叫時會沿用第一張貼圖，所以直接用 RenderingServer
func _quad_tex(ci: CanvasItem, pts: Array, col: Color, u0: float, u1: float, v0: float, v1: float, tex: Texture2D) -> void:
	RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), PackedInt32Array(QUAD_IDX), PackedVector2Array(pts),
		PackedColorArray([col, col, col, col]), PackedVector2Array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]),
		PackedInt32Array(), PackedFloat32Array(), tex.get_rid())


func _quad_grad(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, d: Vector2, ct: Color, cb: Color) -> void:
	ci.draw_primitive(PackedVector2Array([a, b, c, d]), PackedColorArray([ct, ct, cb, cb]), PackedVector2Array())


func _ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 28:
		var a := TAU * k / 28.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_colored_polygon(pts, col)


func _text(ci: CanvasItem, s: String, x: float, y: float, size: int, col: Color, outline := 6, ocol := Color(0, 0, 0, 0.9)) -> void:
	var pos := Vector2(x - 480.0, y)
	if outline > 0:
		ci.draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_CENTER, 960.0, size, outline, ocol)
	ci.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_CENTER, 960.0, size, col)


# ------------------------------------------------------------------
# 背景：夜晚街頭的沙威瑪攤
# ------------------------------------------------------------------
func _draw_bg(ci: CanvasItem) -> void:
	_quad_grad(ci, Vector2(-20, -20), Vector2(W + 20, -20), Vector2(W + 20, 330), Vector2(-20, 330), Color(0.05, 0.03, 0.12), Color(0.36, 0.12, 0.22))
	var span := 26 * 74.0
	var off := fposmod(-phi * 115.0, span)
	for b in buildings:
		var x := fposmod(float(b["x"]) + off, span) - 80.0
		if x > W + 20:
			continue
		var bh := float(b["h"])
		var bw := float(b["w"])
		var y0 := 330.0 - bh
		ci.draw_rect(Rect2(x, y0, bw, bh), Color(0.1, 0.07, 0.16))
		var rs := int(b["s"])
		for wy in range(int(y0) + 10, 320, 16):
			for wx in range(int(x) + 7, int(x + bw) - 8, 13):
				rs = (rs * 1103515245 + 12345) & 0x7fffffff
				if rs % 5 < 2:
					ci.draw_rect(Rect2(wx, wy, 6, 8), Color(1.0, 0.85, 0.45, 0.55))
	var nx := fposmod(220.0 - phi * 130.0, 1400.0) - 220.0
	var glow := 0.75 + 0.25 * sin(t * 9.0) * (1.0 if fmod(t, 4.0) < 3.6 else 0.0)
	ci.draw_rect(Rect2(nx - 6, 150, 182, 56), Color(0.08, 0.02, 0.1))
	_text(ci, "SHAWARMA", nx + 85, 190, 30, Color(1.0, 0.35, 0.7, glow), 10, Color(1.0, 0.2, 0.6, 0.25 * glow))
	var wall_top := 300.0
	_quad_grad(ci, Vector2(-20, wall_top), Vector2(W + 20, wall_top), Vector2(W + 20, FLOOR_Y), Vector2(-20, FLOOR_Y), Color(0.2, 0.17, 0.24), Color(0.13, 0.1, 0.16))
	var toff := fposmod(-phi * 140.0, 48.0)
	for x in range(-48, int(W) + 48, 48):
		ci.draw_line(Vector2(x + toff, wall_top), Vector2(x + toff, FLOOR_Y), Color(0, 0, 0, 0.25), 2)
	for y in range(int(wall_top), int(FLOOR_Y), 24):
		ci.draw_line(Vector2(0, y), Vector2(W, y), Color(0, 0, 0, 0.25), 2)
	ci.draw_rect(Rect2(-20, wall_top - 8, W + 40, 10), Color(0.55, 0.57, 0.62))
	# 烤爐加熱板
	var hx := CX - 190.0
	var htop := 50.0
	ci.draw_rect(Rect2(hx, htop, 380, CYL_BOT - htop + 18), Color(0.16, 0.16, 0.2))
	ci.draw_rect(Rect2(hx + 8, htop + 8, 364, CYL_BOT - htop + 2), Color(0.08, 0.06, 0.08))
	for k in 9:
		var y := htop + 20.0 + k * 44.0
		var fl := 0.75 + 0.25 * sin(t * 6.0 + k * 1.7)
		ci.draw_rect(Rect2(hx + 16, y, 348, 16), Color(1.0, 0.35, 0.05, 0.35 * fl))
		ci.draw_rect(Rect2(hx + 16, y + 4, 348, 8), Color(1.0, 0.65, 0.2, 0.9 * fl))
	# 上方軌道 (沙威瑪從這裡滑進來)
	ci.draw_rect(Rect2(-20, 14, W + 40, 10), Color(0.42, 0.44, 0.5))
	ci.draw_rect(Rect2(-20, 14, W + 40, 3), Color(0.75, 0.77, 0.82))
	# 地板
	_quad_grad(ci, Vector2(-20, FLOOR_Y), Vector2(W + 20, FLOOR_Y), Vector2(W + 20, H + 20), Vector2(-20, H + 20), Color(0.32, 0.3, 0.36), Color(0.12, 0.1, 0.14))
	ci.draw_line(Vector2(0, FLOOR_Y), Vector2(W, FLOOR_Y), Color(0.75, 0.75, 0.82), 2)
	var foff := fposmod(-phi * 150.0, 80.0)
	for k in range(-8, 9):
		var x0 := CX + k * 80.0 + foff
		ci.draw_line(Vector2(x0, FLOOR_Y), Vector2(CX + (x0 - CX) * 1.9, H), Color(0, 0, 0, 0.3), 2)
	for y in [FLOOR_Y + 18.0, FLOOR_Y + 42.0]:
		ci.draw_line(Vector2(0, y), Vector2(W, y), Color(0, 0, 0, 0.25), 2)


# ------------------------------------------------------------------
# 沙威瑪本體 (貼圖)
# ------------------------------------------------------------------
func _draw_shawarma(ci: CanvasItem) -> void:
	var s := shaw
	if s == null or (state == "play" and shaw_state == "explode"):
		return
	var cx := s.cx
	# 底盤 + 烤叉 + 吊架
	_ellipse(ci, Vector2(cx, s.bot + 10), s.r_max + 24, (s.r_max + 24) * Shawarma.ELL + 4, Color(0, 0, 0, 0.35))
	_ellipse(ci, Vector2(cx, s.bot + 6), s.r_max + 18, (s.r_max + 18) * Shawarma.ELL, Color(0.24, 0.25, 0.3))
	_ellipse(ci, Vector2(cx, s.bot + 1), s.r_max + 14, (s.r_max + 14) * Shawarma.ELL, Color(0.52, 0.54, 0.6))
	ci.draw_rect(Rect2(cx - 6, 20, 12, s.top - 10), Color(0.5, 0.52, 0.58))
	ci.draw_rect(Rect2(cx - 6, 20, 4, s.top - 10), Color(0.85, 0.87, 0.92))
	ci.draw_rect(Rect2(cx - 22, 10, 44, 18), Color(0.3, 0.3, 0.36))

	var order: Array = []
	for c in NCOL:
		var a0 := s.col_angle(c, phi)
		order.append([cos(a0 + STEP * 0.5), c, a0])
	order.sort_custom(func(x, y): return x[0] < y[0])

	# 頂面
	var capcol := PackedColorArray([Color(0.4, 0.2, 0.08)])
	var capc := Vector2(cx, s.top)
	for c in NCOL:
		var a0 := c * STEP + s.spin - phi
		var r0 := s.cell_radius(c * s.nrow)
		ci.draw_primitive(PackedVector2Array([capc, s.pp(r0, a0, s.top), s.pp(r0, a0 + STEP, s.top)]), capcol, PackedVector2Array())
	_ellipse(ci, capc, s.r_core * 0.9, s.r_core * 0.9 * Shawarma.ELL, Color(0.52, 0.26, 0.1))
	# 頂端插一顆檸檬 / 番茄 / 辣椒 (真的沙威瑪攤會這樣放)
	var top_col := Color(1.0, 0.82, 0.15)
	if s.kind == "beef":
		top_col = Color(0.9, 0.2, 0.12)
	elif s.kind == "spicy":
		top_col = Color(0.95, 0.1, 0.05)
	var tr := 20.0 if s.is_boss else 15.0
	var tp := capc + Vector2(0, -tr + 4)
	if s.kind == "spicy":
		_ellipse(ci, tp + Vector2(0, -4), 7, tr + 2, top_col)
		ci.draw_line(tp + Vector2(0, -tr - 4), tp + Vector2(4, -tr - 12), Color(0.2, 0.6, 0.15), 4)
	else:
		_ellipse(ci, tp, tr, tr * 0.92, top_col.darkened(0.25))
		_ellipse(ci, tp + Vector2(-1.5, -1.5), tr - 2.5, tr * 0.92 - 2.5, top_col)
		_ellipse(ci, tp + Vector2(-tr * 0.35, -tr * 0.4), tr * 0.28, tr * 0.2, Color(1, 1, 0.9, 0.85))
	ci.draw_rect(Rect2(cx - 3, tp.y - tr - 16, 6, 12), Color(0.8, 0.82, 0.88))

	var pulse := 0.5 + 0.5 * sin(t * (10.0 if s.core_phase else 3.0))
	var vtot := 6.0 * ROW_H   # 貼圖高度代表 6 列
	for item in order:
		var cm: float = item[0]
		if cm < -0.3:
			continue
		var c: int = item[1]
		var a0: float = item[2]
		var a1 := a0 + STEP
		var am := a0 + STEP * 0.5
		var light := 0.38 + 0.72 * clampf(cos(am + 0.45), 0.0, 1.0)
		var u0 := float(c) / NCOL
		var u1 := float(c + 1) / NCOL
		# 沙威核
		var core_col := Color(light, light, light)
		if s.core_phase:
			core_col = core_col.lerp(Color(1.0, 0.55, 0.3), 0.3 + 0.3 * pulse)
			if s.core_flash > 0.0:
				core_col = Color(1.6, 1.6, 1.6)
		_quad_tex(ci, [s.pp(s.r_core, a0, s.top), s.pp(s.r_core, a1, s.top), s.pp(s.r_core, a1, s.bot), s.pp(s.r_core, a0, s.bot)], core_col, u0, u1, 0.0, (s.bot - s.top) / vtot, core_tex)

		for r in s.nrow:
			var i := c * s.nrow + r
			var m := s.meat[i]
			var yt := s.row_y(r)
			var yb := yt + ROW_H
			var v0 := (yt - s.top) / vtot
			var v1 := (yb - s.top) / vtot
			if m <= 0.0:
				if s.seed_t[i] > 0.0 and cm > 0.0:
					# 肉芽在核上蠢蠢欲動
					var sp := s.seed_t[i] / s.seed_delay
					var ym := (yt + yb) * 0.5
					var wob := sin(t * 18.0 + s.rnd[i] * 9.0) * 2.0 * sp
					var rr := s.r_core + 2.0 + 4.0 * sp
					_quad_tex(ci, [s.pp(rr, a0 + STEP * 0.15, ym - 10 * sp - wob), s.pp(rr, a1 - STEP * 0.15, ym - 10 * sp + wob), s.pp(rr, a1 - STEP * 0.15, ym + 10 * sp), s.pp(rr, a0 + STEP * 0.15, ym + 10 * sp)],
						Color(1, 0.8, 0.8, 0.3 + 0.6 * sp), u0, u1, v0, v1, raw_tex)
				continue
			var rad := s.cell_radius(i)
			var tt := m / Shawarma.MEAT_MAX
			var col := Color(s.tint.r * light, s.tint.g * light, s.tint.b * light)
			if s.flash[i] > 0.0:
				col = col.lerp(Color(1.4, 1.3, 1.2), 0.5)
			var raw_a := maxf(s.fresh[i], (1.0 - tt) * 0.55)
			var raw_col := Color(light, light, light, raw_a)
			# 上方那格比較薄 → 露出這格頂面 (切面，用生肉圖)
			if r > 0:
				var ra := s.cell_radius(i - 1)
				if ra < rad - 0.5:
					_quad_tex(ci, [s.pp(ra, a0, yt), s.pp(ra, a1, yt), s.pp(rad, a1, yt), s.pp(rad, a0, yt)], Color(light * 1.1, light, light), u0, u1, v0, v0 + 0.04, raw_tex)
			# 旁邊那格比較薄 → 露出側面
			var nc := (c + 1) % NCOL if am < 0.0 else (c - 1 + NCOL) % NCOL
			var sa := a1 if am < 0.0 else a0
			var rn := s.cell_radius(nc * s.nrow + r)
			if rn < rad - 0.5:
				_quad_tex(ci, [s.pp(rn, sa, yt), s.pp(rad, sa, yt), s.pp(rad, sa, yb), s.pp(rn, sa, yb)], Color(light * 0.75, light * 0.6, light * 0.6), u0, u0 + 0.01, v0, v1, raw_tex)
			# 正面：一片一片疊起來的薄肉，邊緣凹凸不平 (參考真的沙威瑪)
			var c1 := (c + 1) % NCOL
			var shh := ROW_H / Shawarma.SLICES
			var jag_amp := 7.0 * clampf(tt * 1.5, 0.2, 1.0)
			var prev0 := 0.0
			var prev1 := 0.0
			for k in Shawarma.SLICES:
				var kk := r * Shawarma.SLICES + k
				var j0 := s.slice_jag(c, kk)
				var j1 := s.slice_jag(c1, kk)
				var r0 := rad + j0 * jag_amp
				var r1 := rad + j1 * jag_amp
				var ys := yt + k * shh
				var ye := ys + shh
				var vs := v0 + (v1 - v0) * k / Shawarma.SLICES
				var ve := vs + (v1 - v0) / Shawarma.SLICES
				var br := 1.0 + (j0 + j1) * 0.18
				var ctop := Color(col.r * br * 1.18, col.g * br * 1.12, col.b * br * 1.0)   # 上緣烤得酥脆金黃
				var cbot := Color(col.r * br * 0.62, col.g * br * 0.55, col.b * br * 0.5)  # 下緣是片與片之間的陰影
				# 這片比上一片凸出來 → 看得到它的頂面
				if k > 0 and (r0 > prev0 + 1.0 or r1 > prev1 + 1.0):
					_quad(ci, [s.pp(minf(prev0, r0), a0, ys), s.pp(minf(prev1, r1), a1, ys), s.pp(r1, a1, ys), s.pp(r0, a0, ys)], ctop.lightened(0.12))
				var sl := [s.pp(r0, a0, ys), s.pp(r1, a1, ys), s.pp(r1, a1, ye), s.pp(r0, a0, ye)]
				_quad_tex2(ci, sl, ctop, cbot, u0, u1, vs, ve, meat_tex)
				if raw_a > 0.03:
					_quad_tex2(ci, sl, Color(light * 1.05, light, light, raw_a), Color(light * 0.7, light * 0.6, light * 0.6, raw_a), u0, u1, vs, ve, raw_tex)
				prev0 = r0
				prev1 = r1
			if cm > 0.3:
				# 生肉表面冒泡泡 (長肉中)
				if s.fresh[i] > 0.25:
					for k in 2:
						var ph := fmod(t * 0.9 + s.rnd[i] * 3.0 + k * 0.5, 1.0)
						var bp := s.pp(rad + 1.0, a0 + STEP * (0.25 + 0.5 * fmod(s.rnd[i] * (k + 3.7), 1.0)), yt + ROW_H * (0.3 + 0.4 * k))
						ci.draw_arc(bp, 1.5 + 3.5 * ph, 0, TAU, 10, Color(1, 0.9, 0.9, (1.0 - ph) * s.fresh[i] * 0.8), 1.2)
				# 刀痕
				if s.cut[i] > 0.0:
					var cp := s.pp(rad + 1.0, am, (yt + yb) * 0.5)
					ci.draw_line(cp + Vector2(-14, -10), cp + Vector2(14, 10), Color(1, 0.85, 0.7, s.cut[i] * 5.0), 3.0)

	# 往下流的肉汁
	for d in s.drips:
		var c: int = d["c"]
		var a := s.col_angle(c, phi) + STEP * 0.5
		if cos(a) < 0.15:
			continue
		var y := float(d["y"])
		var r := clampi(int((y - s.top) / ROW_H), 0, s.nrow - 1)
		var rad := s.cell_radius(c * s.nrow + r) + 1.5
		var p := s.pp(rad, a, y)
		var ln := float(d["len"])
		_ellipse(ci, p, 2.6, ln * 0.5, Color(0.75, 0.42, 0.08, 0.85))
		ci.draw_line(p + Vector2(0, -ln * 0.5), p, Color(0.85, 0.55, 0.15, 0.6), 2.0)

	# 沙威核的眼睛
	if s.core_phase:
		var es := 1.0 if s.is_boss else 0.7
		var ec := Vector2(cx, (s.top + s.bot) * 0.5 + Shawarma.ELL * s.r_core)
		_ellipse(ci, ec, 46 * es, 30 * es, Color(0.1, 0.02, 0.02))
		_ellipse(ci, ec, 40 * es, 24 * es, Color(1, 0.95, 0.8) if s.core_flash <= 0.0 else Color(1, 0.3, 0.3))
		var look := clampf((p_pos.x - cx) / 200.0, -1.0, 1.0)
		var iris := ec + Vector2(look * 20.0 * es, clampf((p_pos.y - 60 - ec.y) / 200.0, -1, 1) * 8.0 * es)
		_ellipse(ci, iris, 15 * es, 15 * es, Color(0.85, 0.1, 0.05))
		_ellipse(ci, iris, 6 * es, 9 * es, Color(0.05, 0, 0))
		ci.draw_line(ec + Vector2(-46, -40) * es, ec + Vector2(-8, -28) * es, Color(0.1, 0.02, 0.02), 6 * es)
		ci.draw_line(ec + Vector2(46, -40) * es, ec + Vector2(8, -28) * es, Color(0.1, 0.02, 0.02), 6 * es)


## 加亮層：油亮反光、烤爐映在邊緣的橘光、沙威核發光
func _draw_glow(ci: CanvasItem) -> void:
	var s := shaw
	if s == null or (state == "play" and shaw_state == "explode"):
		return
	var pulse := 0.5 + 0.5 * sin(t * (10.0 if s.core_phase else 3.0))
	for c in NCOL:
		var a0 := s.col_angle(c, phi)
		var a1 := a0 + STEP
		var am := a0 + STEP * 0.5
		var cm := cos(am)
		if cm < 0.0:
			continue
		var spec := pow(maxf(0.0, cos(am + 0.55)), 14.0) * 0.32
		var rim := pow(clampf(1.0 - cm, 0.0, 1.0), 4.0) * 0.55
		for r in s.nrow:
			var i := c * s.nrow + r
			var yt := s.row_y(r)
			if s.meat[i] <= 0.0:
				if s.core_phase:
					var g := Color(0.6, 0.25, 0.05) * (0.3 + 0.4 * pulse) * cm
					_quad(ci, [s.pp(s.r_core, a0, yt), s.pp(s.r_core, a1, yt), s.pp(s.r_core, a1, yt + ROW_H), s.pp(s.r_core, a0, yt + ROW_H)], g)
				continue
			var rad := s.cell_radius(i)
			var pts := [s.pp(rad, a0, yt), s.pp(rad, a1, yt), s.pp(rad, a1, yt + ROW_H), s.pp(rad, a0, yt + ROW_H)]
			var gl := Color(spec * 1.0, spec * 0.85, spec * 0.6) + Color(rim, rim * 0.4, rim * 0.05)
			if s.bulge[i] > 0.0:
				gl += Color(0.3, 0.12, 0.1) * s.bulge[i]
			_quad(ci, pts, gl)
			# 油花閃光
			if s.rnd[i] > 0.6 and cm > 0.4:
				var tw := pow(maxf(0.0, sin(t * 3.0 + s.rnd[i] * 40.0)), 8.0)
				if tw > 0.05:
					var gp := s.pp(rad + 1.0, a0 + STEP * s.rnd[i], yt + ROW_H * fmod(s.rnd[i] * 7.3, 1.0))
					var gc := Color(1, 0.9, 0.6, 1) * tw * 0.9
					ci.draw_line(gp + Vector2(-5, 0), gp + Vector2(5, 0), gc, 1.5)
					ci.draw_line(gp + Vector2(0, -5), gp + Vector2(0, 5), gc, 1.5)


# ------------------------------------------------------------------
# 特效層
# ------------------------------------------------------------------
func _draw_fx_back(ci: CanvasItem) -> void:
	for g in ghosts:
		var fr: Dictionary = g["fr"]
		var tx: Texture2D = fr["tex"]
		var f := float(g["f"])
		ci.draw_set_transform(Vector2(g["p"]), 0.0, Vector2(0.5 * f, 0.5))
		ci.draw_texture(tx, Vector2(-float(fr["ax"]) * tx.get_width(), -float(fr["ay"]) * tx.get_height()), Color(0.3, 1.0, 0.6, float(g["life"]) * 2.4))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for d in drops:
		var x := float(d["x"])
		var y := float(d["y"])
		if float(d["warn"]) > 0.0:
			var s := 1.0 - float(d["warn"]) / 0.7
			_ellipse(ci, Vector2(x, y + 4), 4 + 5 * s, 3 + 6 * s, Color(1.0, 0.8, 0.2, 0.8))
			ci.draw_line(Vector2(x, y + 14), Vector2(x, FLOOR_Y), Color(1, 0.8, 0.2, 0.12 * s), 10)
		else:
			_ellipse(ci, Vector2(x, y - 8), 6, 12, Color(1.0, 0.7, 0.1, 0.5))
			_ellipse(ci, Vector2(x, y), 9, 11, Color(1.0, 0.85, 0.3))
			_ellipse(ci, Vector2(x - 3, y - 3), 3, 4, Color(1, 1, 0.9))
	for w in waves:
		var x := float(w["x"])
		for k in 3:
			var hh := 46.0 - k * 12.0
			ci.draw_line(Vector2(x - float(w["dir"]) * k * 8.0, FLOOR_Y), Vector2(x - float(w["dir"]) * k * 8.0, FLOOR_Y - hh), Color(1.0, 0.5 + k * 0.2, 0.15, 0.9 - k * 0.25), 7.0 - k * 2.0)
	for p in particles:
		var k: String = p["k"]
		if k == "steam" or k == "smoke":
			var c: Color = p["c"]
			c.a *= clampf(float(p["life"]) / float(p["max"]) * 1.5, 0.0, 1.0)
			ci.draw_circle(Vector2(p["p"]), float(p["s"]), c)


func _draw_fx_front(ci: CanvasItem) -> void:
	for p in particles:
		var k: String = p["k"]
		var al := clampf(float(p["life"]) / float(p["max"]) * 2.0, 0.0, 1.0)
		var pos := Vector2(p["p"])
		var s := float(p["s"])
		if k == "juice":
			# 亮晶晶的肉汁滴：沿著速度方向拉長
			var v := Vector2(p["v"])
			var c: Color = p["c"]
			c.a = al
			var dir := v.normalized() if v.length() > 1.0 else Vector2.DOWN
			var ln := clampf(v.length() * 0.02, 1.0, 3.0)
			ci.draw_line(pos - dir * s * ln, pos, c, s)
			ci.draw_circle(pos, s * 0.55, c)
			ci.draw_circle(pos - Vector2(s * 0.2, s * 0.2), s * 0.22, Color(1, 0.95, 0.8, al * 0.9))
		elif k == "chunk":
			ci.draw_set_transform(pos, float(p["rot"]), Vector2.ONE)
			var reg: Rect2 = p["reg"]
			var asp := reg.size.y / reg.size.x
			ci.draw_texture_rect_region(meat_tex, Rect2(-s * 0.5, -s * 0.5 * asp, s, s * asp), reg, Color(1, 1, 1, al))
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif k == "pink":
			var c: Color = p["c"]
			c.a = al
			ci.draw_circle(pos, s, c)
	for p in popups:
		var a := clampf(float(p["life"]) * 2.0, 0.0, 1.0)
		var c: Color = p["c"]
		c.a = a
		_text(ci, String(p["s"]), Vector2(p["p"]).x, Vector2(p["p"]).y, int(p["size"]), c, 5, Color(0, 0, 0, 0.8 * a))


## 光劍刀光：粗的新月形，快速劃開再淡出 (三層：外光暈 / 綠色本體 / 白色刀芯)
func _slash_fx(c: Vector2, r: float, a0: float, sweep: float, w: float, life: float) -> void:
	life *= 1.3
	w *= 1.35
	arcs.append({"c": c, "r": r, "a0": a0, "sweep": sweep, "w": w, "life": life, "max": life, "echo": 0.0})
	# 殘影：稍微落後、大一點、比較淡
	arcs.append({"c": c, "r": r * 1.12, "a0": a0 - sweep * 0.08, "sweep": sweep, "w": w * 0.7, "life": life * 1.25, "max": life * 1.25, "echo": 1.0})


func _draw_crescent(ci: CanvasItem, a: Dictionary) -> void:
	var p := 1.0 - float(a["life"]) / float(a["max"])
	var reveal := 1.0 - pow(1.0 - clampf(p / 0.4, 0.0, 1.0), 3.0)
	var fade := 1.0 if p < 0.4 else clampf((1.0 - p) / 0.6, 0.0, 1.0)
	var tail := maxf(0.0, reveal - 0.95)
	var c: Vector2 = a["c"]
	var r := float(a["r"]) * (1.0 + 0.08 * p)
	var a0 := float(a["a0"])
	var sweep := float(a["sweep"])
	var w := float(a["w"])
	var n := 26
	for layer in 3:
		var ws: float = [2.6, 1.15, 0.42][layer]
		var base: Color = [Color(0.1, 0.9, 0.35, 0.55), Color(0.4, 1.0, 0.5, 1.0), Color(1, 1, 1, 1)][layer]
		if float(a.get("echo", 0.0)) > 0.0:
			base.a *= 0.35
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		var idx := PackedInt32Array()
		for k in n + 1:
			var u := float(k) / n
			var tu := lerpf(tail, reveal, u)
			var ang := a0 + sweep * tu
			var th := w * ws * pow(u, 0.6) * (1.0 - pow(u, 10.0) * 0.6)
			var d := Vector2(cos(ang), sin(ang))
			# 新月：外緣在半徑上，內緣往圓心縮 → 中間最粗
			pts.append(c + d * (r + th * 0.35))
			pts.append(c + d * (r - th * 0.65))
			var col := base
			col.a *= fade * pow(u, 0.8)
			cols.append(col)
			cols.append(col)
			if k > 0:
				var i := k * 2
				idx.append_array([i - 2, i - 1, i, i - 1, i + 1, i])
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), idx, pts, cols)
	# 刀尖的速度線
	if p < 0.5:
		var ang := a0 + sweep * reveal
		var d := Vector2(cos(ang), sin(ang))
		var tg := Vector2(-d.y, d.x) * signf(sweep)
		for j in 3:
			var o := c + d * (r + (j - 1) * w * 0.4)
			ci.draw_line(o, o - tg * (30.0 + j * 12.0) * (1.0 - p * 2.0), Color(0.8, 1.0, 0.85, 0.7 * (1.0 - p * 2.0)), 2.0)


func _draw_fx_add(ci: CanvasItem) -> void:
	for a in arcs:
		_draw_crescent(ci, a)
	for p in particles:
		if p["k"] == "impact":
			# 命中的星形閃光
			var k := 1.0 - float(p["life"]) / float(p["max"])
			var pos := Vector2(p["p"])
			var sz := float(p["s"]) * (0.6 + k * 1.2)
			var al := 1.0 - k
			for j in 4:
				var ang := float(p["rot"]) + j * PI * 0.5
				var d := Vector2(cos(ang), sin(ang))
				ci.draw_line(pos - d * sz, pos + d * sz, Color(0.6, 1.0, 0.7, al * 0.8), 5.0 * al + 1.0)
				ci.draw_line(pos - d * sz * 0.6, pos + d * sz * 0.6, Color(1, 1, 1, al), 2.0)
			ci.draw_circle(pos, sz * 0.35 * al + 2.0, Color(1, 1, 0.9, al))
	for p in particles:
		if p["k"] == "spark":
			var c: Color = p["c"]
			c.a = clampf(float(p["life"]) / float(p["max"]) * 2.0, 0.0, 1.0)
			var v := Vector2(p["v"])
			ci.draw_line(Vector2(p["p"]), Vector2(p["p"]) - v * 0.03, c, float(p["s"]))
	if state == "play" and shaw_state == "explode" and shaw:
		var k := clampf(1.0 - shaw_t / 0.5, 0.0, 1.0)
		ci.draw_circle(Vector2(shaw.cx, (shaw.top + shaw.bot) * 0.5), (shaw.r_max + 80.0) * (1.2 - k * 0.6), Color(1, 0.6, 0.2, 0.5 * k))
	if flash_screen > 0.0:
		ci.draw_rect(Rect2(-20, -20, W + 40, H + 40), Color(1, 0.9, 0.7, flash_screen * 3.0))


# ------------------------------------------------------------------
# HUD
# ------------------------------------------------------------------
func _fmt_time(sec: float) -> String:
	return "%d:%04.1f" % [int(sec) / 60, fmod(sec, 60.0)]


func _draw_hud(ci: CanvasItem) -> void:
	if state == "title":
		_draw_title(ci)
		return
	if state == "story":
		_draw_story(ci)
		return
	# HP
	var hx := 22.0
	var hy := 70.0
	var segs := 20
	ci.draw_rect(Rect2(hx - 5, hy - 5, 28, segs * 8 + 10), Color(0, 0, 0, 0.75))
	ci.draw_rect(Rect2(hx - 5, hy - 5, 28, segs * 8 + 10), Color(0.9, 0.9, 1.0, 0.8), false, 2.0)
	for k in segs:
		var on := k < int(ceil(p_hp / P_HP_MAX * segs))
		var y := hy + (segs - 1 - k) * 8.0
		ci.draw_rect(Rect2(hx, y, 18, 6), Color(1.0, 0.95, 0.5) if on else Color(0.2, 0.2, 0.25))
		if on:
			ci.draw_rect(Rect2(hx, y, 18, 2), Color(1, 1, 1, 0.8))
	var head: Texture2D = anims["idle"]["frames"][0]["tex"]
	var hw := float(head.get_width())
	ci.draw_texture_rect_region(head, Rect2(hx - 12, hy + segs * 8 + 8, 42, 42), Rect2(hw * 0.28, 0, hw * 0.5, hw * 0.5))

	var st: Dictionary = STAGES[stage]
	_text(ci, "STAGE %d  %s" % [stage + 1, st["name"]], 240, 26, 17, Color(1, 1, 1), 4)
	_text(ci, "SCORE %07d" % score, 700, 26, 17, Color(1, 0.95, 0.6), 4)
	_text(ci, _fmt_time(stage_time), 700, 48, 15, Color(0.8, 1, 0.9), 4)

	# 沙威瑪排隊進度
	var q: Array = st["queue"]
	var qx := CX - q.size() * 13.0
	for i in q.size():
		var boss := String(q[i]) == "boss"
		var rx := qx + i * 26.0 + 13.0
		var col := Color(0.3, 0.28, 0.3)
		if i > shaw_idx or (i == shaw_idx and state == "play" and shaw_state != "explode"):
			col = Color(0.75, 0.4, 0.15) if not boss else Color(0.9, 0.25, 0.15)
		if i == shaw_idx and state == "play":
			ci.draw_rect(Rect2(rx - 11, 14, 22, 30), Color(1, 1, 0.6, 0.5 + 0.3 * sin(t * 8)), false, 2.0)
		var hh := 22.0 if boss else 16.0
		ci.draw_rect(Rect2(rx - 6, 40 - hh, 12, hh), col)
		ci.draw_line(Vector2(rx, 40 - hh - 4), Vector2(rx, 42), Color(0.8, 0.8, 0.85), 1.5)

	# 目前這根的肉量 / 沙威核
	if shaw and state == "play" and shaw_state == "fight":
		var bx := CX - 150.0
		var by := 52.0
		var bw := 300.0
		ci.draw_rect(Rect2(bx - 3, by - 3, bw + 6, 18), Color(0, 0, 0, 0.75))
		if shaw.core_phase:
			var f := float(shaw.core_hp) / float(shaw.core_hp_max)
			ci.draw_rect(Rect2(bx, by, bw * f, 12), Color(1.0, 0.3, 0.15).lerp(Color(1, 1, 0.5), 0.5 + 0.5 * sin(t * 12)))
			_text(ci, "沙威核", bx - 38, by + 12, 15, Color(1, 0.6, 0.4), 4)
			_text(ci, "肉再生倒數 %.1f" % maxf(0.0, shaw.core_t), CX, by + 36, 17, Color(1, 0.85, 0.3) if shaw.core_t > 2 else Color(1, 0.3, 0.3), 5)
		else:
			var f := shaw.ratio()
			ci.draw_rect(Rect2(bx, by, bw * f, 12), Color(0.75, 0.38, 0.15))
			ci.draw_rect(Rect2(bx, by, bw * f, 4), Color(0.95, 0.6, 0.4))
			_text(ci, shaw.title, CX, by + 34, 15, Color(1, 0.85, 0.7), 4)
		_draw_minimap(ci)

	if combo >= 3 and state == "play":
		var sc := 1.0 + clampf(combo_t - 1.0, 0.0, 0.2) * 2.0
		_text(ci, "%d HIT" % combo, 860, 200, int(28 * sc), Color(1, 0.8, 0.3), 6)

	if stage == 0 and state == "play" and state_t < 9.0 and not DisplayServer.is_touchscreen_available():
		_text(ci, "←→ 移動 (走到邊緣會繞著沙威瑪轉)   Z 跳(可二段跳)   X 斬(連打!)   C 衝刺   ↑+X 上斬", CX, 528, 14, Color(1, 1, 1, clampf(9.0 - state_t, 0, 1)), 4)

	if banner_t > 0.0:
		var a := clampf(banner_t * 2.0, 0.0, 1.0)
		_text(ci, banner, CX, 230, 44, Color(1, 0.9, 0.3, a), 10, Color(0.3, 0.05, 0, 0.9 * a))
		if banner_sub != "":
			_text(ci, banner_sub, CX, 270, 22, Color(1, 1, 1, a), 6, Color(0, 0, 0, 0.9 * a))

	if state == "gameover":
		ci.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, clampf(state_t, 0, 0.6)))
		_text(ci, "GAME OVER", CX, 220, 56, Color(1, 0.3, 0.2), 10)
		_text(ci, "沙威瑪的肉長得太快了……", CX, 262, 22, Color(1, 1, 1), 5)
		if state_t > 1.2:
			_text(ci, "按 X / Enter 或點擊畫面 重新挑戰這一關", CX, 310, 20, Color(1, 1, 0.6, 0.6 + 0.4 * sin(t * 6)), 5)
	elif state == "ending":
		ci.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, clampf(state_t * 0.5, 0, 0.65)))
		_text(ci, "全部沙威瑪 斬殺完成！", CX, 170, 46, Color(1, 0.9, 0.3), 10)
		_text(ci, "SCORE %d" % score, CX, 225, 30, Color(1, 0.95, 0.6), 6)
		_text(ci, "總時間 %s　最高連擊 %d" % [_fmt_time(total_time), best_combo], CX, 262, 22, Color(1, 1, 1), 6)
		_text(ci, "柯基英雄拯救了夜市……今晚吃沙威瑪捲餅！", CX, 300, 22, Color(0.8, 1, 0.9), 5)
		if state_t > 2.0:
			_text(ci, "按 X / Enter 或點擊畫面 回到標題", CX, 350, 20, Color(1, 1, 0.6, 0.6 + 0.4 * sin(t * 6)), 5)


func _draw_minimap(ci: CanvasItem) -> void:
	var mc := Vector2(892, 110)
	var mr := 44.0
	ci.draw_circle(mc, mr + 10, Color(0, 0, 0, 0.55))
	for f in 6:
		var b0 := f * Shawarma.COLS_PER_FACE * STEP + shaw.spin - phi
		var b1 := b0 + Shawarma.COLS_PER_FACE * STEP
		var p0 := mc + mr * Vector2(sin(b0), cos(b0) * 0.8)
		var p1 := mc + mr * Vector2(sin(b1), cos(b1) * 0.8)
		var fm := shaw.face_meat(f)
		var col := Color(0.25, 0.22, 0.3).lerp(Color(0.85, 0.42, 0.16), fm)
		if fm <= 0.0:
			col = Color(0.3, 0.8, 0.45) if not shaw.core_phase else Color(1, 0.5, 0.2)
		ci.draw_colored_polygon(PackedVector2Array([mc, p0, p1]), col)
		ci.draw_line(p0, p1, Color(1, 1, 1, 0.8), 2)
		var lc := (mc + p0 + p1) / 3.0
		_text(ci, str(f + 1), lc.x, lc.y + 6, 14, Color(1, 1, 1), 3)
	var pm := mc + Vector2(0, mr * 0.8 + 14)
	ci.draw_colored_polygon(PackedVector2Array([pm + Vector2(0, -8), pm + Vector2(-7, 4), pm + Vector2(7, 4)]), Color(0.4, 1, 0.6))


func _draw_story(ci: CanvasItem) -> void:
	var img = story_imgs[story_i]
	var fade := clampf(state_t * 3.0, 0.0, 1.0)
	if img != null:
		var tx: Texture2D = img
		var sc := minf(W / tx.get_width(), H / tx.get_height())
		var sz := Vector2(tx.get_width(), tx.get_height()) * sc
		ci.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0))
		# 慢慢推近 (Ken Burns)
		var zoom := 1.0 + 0.04 * minf(state_t, 6.0) / 6.0
		var dsz := sz * zoom
		ci.draw_texture_rect(tx, Rect2((Vector2(W, H) - dsz) * 0.5, dsz), false, Color(1, 1, 1, fade))
	else:
		# 沒有 Gemini 圖時：用遊戲畫面 + 大張主角代替
		var tints := [Color(0.05, 0.02, 0.15, 0.55), Color(0.3, 0.02, 0.02, 0.35), Color(0.0, 0.05, 0.1, 0.6), Color(0.0, 0.1, 0.05, 0.5)]
		ci.draw_rect(Rect2(0, 0, W, H), tints[story_i])
		if story_i >= 2:
			var key := "idle" if story_i == 2 else _resolve_anim("slash3")
			var fr: Dictionary = anims[key]["frames"][0]
			var tx: Texture2D = fr["tex"]
			var h := 300.0
			var sc := h / tx.get_height()
			var x := 300.0 + (1.0 - fade) * -60.0
			ci.draw_texture_rect(tx, Rect2(x - float(fr["ax"]) * tx.get_width() * sc, 430.0 - h, tx.get_width() * sc, h), false, Color(1, 1, 1, fade))
	# 文字框
	ci.draw_rect(Rect2(40, 410, W - 80, 104), Color(0, 0, 0, 0.72))
	ci.draw_rect(Rect2(40, 410, W - 80, 104), Color(1, 0.85, 0.4, 0.8), false, 2.0)
	var txt: String = STORY[story_i]
	var shown := txt.substr(0, int(story_chars))
	ci.draw_string(font, Vector2(64, 450), shown, HORIZONTAL_ALIGNMENT_LEFT, W - 128, 22, Color(1, 1, 1))
	if story_chars >= txt.length():
		_text(ci, "▼", W - 70, 500, 16, Color(1, 0.9, 0.4, 0.5 + 0.5 * sin(t * 6)), 3)
	_text(ci, "點擊 / X 繼續　　C 跳過", W - 120, 30, 14, Color(1, 1, 1, 0.7), 3)
	_text(ci, "%d / %d" % [story_i + 1, STORY.size()], 60, 30, 14, Color(1, 1, 1, 0.7), 3)


func _draw_title(ci: CanvasItem) -> void:
	ci.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.3))
	var x := CX - 150.0
	_text(ci, "奇異果英雄傳 外傳", x, 100, 24, Color(0.7, 1, 0.75), 6)
	_text(ci, "沙威瑪斬", x, 178, 84, Color(1.0, 0.78, 0.25), 14, Color(0.35, 0.08, 0.0))
	_text(ci, "SHAWARMA  SLASH", x, 216, 22, Color(1, 0.5, 0.3), 6)
	_text(ci, "夜市的沙威瑪全都活過來了！", x, 270, 19, Color(1, 1, 1), 5)
	_text(ci, "砍肉要比長肉快，砍光露出沙威核就打爆它，", x, 296, 19, Color(1, 1, 1), 5)
	_text(ci, "一根接一根，越快斬殺分數越高！", x, 322, 19, Color(1, 1, 1), 5)
	_text(ci, "按 Enter / X 或點擊畫面 開始", x, 390, 24, Color(1, 1, 0.5, 0.55 + 0.45 * sin(t * 5)), 6)
	_text(ci, "←→移動  Z跳  X斬  C衝刺  ↑+X上斬", x, 424, 15, Color(0.85, 0.85, 1), 4)


# ==================================================================
# 自動遊玩 (調整難度用)
# ==================================================================
func _bot(dt: float) -> void:
	bot_t += dt
	log_t += dt
	if log_t >= 5.0 and not OS.has_feature("web"):
		log_t = 0.0
		print("[bot] %s stage=%d shaw=%d/%d t=%.0f meat=%.1f%% hp=%.0f score=%d" % [state, stage + 1, shaw_idx + 1, STAGES[stage]["queue"].size(), stage_time, (shaw.ratio() * 100.0 if shaw else 0.0), p_hp, score])
	if state != "play":
		if state == "ending" and not OS.has_feature("web"):
			print("[bot] ENDING total=%.1f score=%d" % [total_time, score])
			get_tree().quit()
		if state == "clear" and not OS.has_feature("web") and state_t < dt * 1.5:
			print("[bot] CLEAR stage=%d time=%.1f" % [stage + 1, stage_time])
		tap = state != "clear"
		return
	if shaw_state == "explode" and not shaw.has_meta("logged") and not OS.has_feature("web"):
		shaw.set_meta("logged", true)
		print("   killed %s in %.1fs" % [shaw.kind, shaw.life_t])
	Input.action_press("attack")
	var want := 0.0
	var high := false
	if shaw.core_phase or shaw_state != "fight":
		want = signf(CX - p_pos.x) if absf(CX - p_pos.x) > 40.0 else 0.0
		high = fmod(bot_t, 2.4) > 1.2
	else:
		# 找最近、肉最多的那一條瞄準
		var tc := 0
		var best := -1e9
		for c in NCOL:
			var cmt := 0.0
			for r in shaw.nrow:
				cmt += shaw.meat[c * shaw.nrow + r]
			if cmt <= 0.0:
				continue
			var d := absf(shaw.col_angle(c, phi) + STEP * 0.5)
			var sc := cmt - d * 120.0
			if sc > best:
				best = sc
				tc = c
		var bd := shaw.col_angle(tc, phi) + STEP * 0.5
		var tx := shaw.cx + shaw.r_max * sin(bd)
		if absf(bd) > 0.35:
			want = signf(bd)
		elif absf(tx - p_pos.x) > 12.0:
			want = signf(tx - p_pos.x)
		elif fmod(bot_t, 0.6) < 0.05:
			want = -float(p_face)
		for r in mini(2, shaw.nrow - 2) + (1 if shaw.nrow >= 6 else 0):
			if shaw.meat[tc * shaw.nrow + r] > 0.0:
				high = true
	Input.action_release("move_left")
	Input.action_release("move_right")
	if want > 0.0:
		Input.action_press("move_right")
	elif want < 0.0:
		Input.action_press("move_left")
	if high:
		Input.action_press("up")
		if p_vel.y < 0.0:
			pass
		elif Input.is_action_pressed("jump"):
			Input.action_release("jump")
		elif p_floor or p_jumps > 0:
			Input.action_press("jump")
	else:
		Input.action_release("up")
		Input.action_release("jump")
