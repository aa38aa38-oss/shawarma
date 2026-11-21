extends Node2D
## 沙威瑪斬 —— 偽 3D 旋轉沙威瑪 + 2D 動作
##
## 沙威瑪是一根直立圓柱，切成 NCOL 直條 × NROW 橫列的「肉格子」。
## 每一格有自己的肉量 (0~100)，肉量決定那一格往外凸多少。
## 畫面是用 x = R·sin(角度)、明暗 = cos(角度) 把圓柱「假」畫出來的，
## 全部都是 2D 多邊形，沒有任何 3D 模型。

const DrawerScript := preload("res://scripts/drawer.gd")

const W := 960.0
const H := 540.0
const CX := 480.0
const FLOOR_Y := 476.0
const CYL_TOP := 80.0
const CYL_BOT := 452.0
const NCOL := 24          # 24 直條 = 6 面 × 4 條
const NROW := 6
const COLS_PER_FACE := 4
const R_CORE := 86.0      # 沙威核半徑
const R_MAX := 152.0      # 肉長滿時的半徑
const ELL := 0.13         # 稍微從上往下看的橢圓感
const MEAT_MAX := 100.0
const ZONE := 70.0        # 主角能自由走動的範圍，超過就轉動視角
const STEP := TAU / NCOL
const P_HP_MAX := 20.0

const STAGES := [
	{"name": "初級沙威瑪", "growth": 5.0, "spin": 0.22, "seed": 2.4, "grease": 3.2, "core_hp": 20, "core_time": 12.0},
	{"name": "辣味沙威瑪", "growth": 8.0, "spin": 0.36, "seed": 1.9, "grease": 2.3, "core_hp": 26, "core_time": 11.0},
	{"name": "超級雙倍沙威瑪", "growth": 10.0, "spin": 0.52, "seed": 1.5, "grease": 1.6, "core_hp": 32, "core_time": 10.0},
]
const SLASH_DMG := 17.0

# ax/ay：腳底中心在圖片中的位置 (比例)
const SPR := {
	"idle": {"ax": 0.50, "ay": 0.99},
	"jump": {"ax": 0.55, "ay": 0.99},
	"slash": {"ax": 0.38, "ay": 0.97},
	"dash": {"ax": 0.55, "ay": 0.90},
	"die": {"ax": 0.50, "ay": 0.97},
}

var font: Font
var tex := {}
var sfx := {}
var bgm: AudioStreamPlayer

var world: Node2D
var bg_layer: Node2D
var shaw_layer: Node2D
var fx_back: Node2D
var fx_front: Node2D
var hud: Node2D
var player_spr: Sprite2D
var touch_layer: CanvasLayer

var state := "title"   # title / play / clear / gameover / ending
var stage := 0
var t := 0.0
var state_t := 0.0
var stage_time := 0.0
var total_time := 0.0
var hitstop := 0.0
var tap := false

var meat := PackedFloat32Array()
var seed_t := PackedFloat32Array()
var flash := PackedFloat32Array()
var cell_rand := PackedFloat32Array()
var spin := 0.0
var phi := 0.0

var core_phase := false
var core_t := 0.0
var core_hp := 0
var core_hp_max := 1
var core_flash := 0.0
var wave_t := 0.0
var waves: Array = []

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
var ghost_t := 0.0

var drops: Array = []
var particles: Array = []
var ghosts: Array = []
var arcs: Array = []
var grease_t := 2.0
var shake := 0.0
var banner := ""
var banner_sub := ""
var banner_t := 0.0
var hit_sfx_cd := 0.0
var buildings: Array = []
var autoplay := false   # 測試用：--autoplay 讓電腦自己玩，用來調整難度
var bot_t := 0.0
var bot_face := -1
var log_t := 0.0


# ==================================================================
# 初始化
# ==================================================================
func _ready() -> void:
	randomize()
	_setup_input()
	font = load("res://assets/font.ttf")
	for n in ["idle", "jump", "slash", "dash", "die"]:
		tex[n] = load("res://assets/hero_%s.png" % n)
	for n in ["slash", "hit", "jump", "hurt", "boom", "core", "splat", "dash"]:
		sfx[n] = load("res://assets/sfx_%s.wav" % n)

	world = Node2D.new()
	add_child(world)
	bg_layer = _make_drawer(world, _draw_bg)
	shaw_layer = _make_drawer(world, _draw_shawarma)
	fx_back = _make_drawer(world, _draw_fx_back)
	player_spr = Sprite2D.new()
	player_spr.centered = false
	player_spr.scale = Vector2(0.5, 0.5)
	world.add_child(player_spr)
	fx_front = _make_drawer(world, _draw_fx_front)

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
	_init_meat()
	p_pos = Vector2(CX - 175, FLOOR_Y)
	autoplay = "--autoplay" in OS.get_cmdline_user_args()
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		autoplay = autoplay or (q is String and "autoplay" in q)


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
	touch_layer = CanvasLayer.new()
	touch_layer.layer = 10
	add_child(touch_layer)
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
		touch_layer.add_child(b)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		tap = true
	elif event is InputEventMouseButton and event.pressed:
		tap = true


func _init_meat() -> void:
	var n := NCOL * NROW
	meat.resize(n)
	seed_t.resize(n)
	flash.resize(n)
	cell_rand.resize(n)
	var off := randf() * TAU
	for c in NCOL:
		for r in NROW:
			var i := c * NROW + r
			var v := 70.0 + 18.0 * sin(c * STEP * 2.0 + off) + 10.0 * cos(r * 1.3 + c * 0.7)
			meat[i] = clampf(v + randf_range(-6, 6), 40.0, MEAT_MAX)
			seed_t[i] = 0.0
			flash[i] = 0.0
			cell_rand[i] = randf()


# ==================================================================
# 主迴圈
# ==================================================================
func _process(delta: float) -> void:
	var dt := minf(delta, 1.0 / 30.0)
	t += dt
	hit_sfx_cd -= dt
	banner_t -= dt
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
				spin += 0.35 * dt
				phi = 0.0
				p_face = 1
				if confirm:
					_start_game()
			"play":
				stage_time += dt
				_update_play(dt)
			"clear":
				_update_play(dt)
				if state_t > 3.6:
					if stage < STAGES.size() - 1:
						_start_stage(stage + 1)
					else:
						state = "ending"
						state_t = 0.0
			"gameover":
				spin += float(STAGES[stage]["spin"]) * dt
				_grow_meat(dt)
				p_vel.y += 1500.0 * dt
				p_pos.y = minf(FLOOR_Y, p_pos.y + p_vel.y * dt)
				if state_t > 1.2 and confirm:
					p_hp = P_HP_MAX
					_start_stage(stage)
			"ending":
				spin += 0.6 * dt
				if state_t > 2.0 and confirm:
					state = "title"
					state_t = 0.0
					_init_meat()
					p_pos = Vector2(CX - 175, FLOOR_Y)
		_update_fx(dt)

	shake = maxf(0.0, shake - dt * 30.0)
	if shake > 0.0:
		world.position = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	else:
		world.position = Vector2.ZERO
	_update_player_sprite()
	bg_layer.queue_redraw()
	shaw_layer.queue_redraw()
	fx_back.queue_redraw()
	fx_front.queue_redraw()
	hud.queue_redraw()


func _start_game() -> void:
	stage = 0
	total_time = 0.0
	p_hp = P_HP_MAX
	if not bgm.playing:
		bgm.play()
	_start_stage(0)


func _start_stage(s: int) -> void:
	stage = s
	_init_meat()
	state = "play"
	state_t = 0.0
	stage_time = 0.0
	core_phase = false
	drops.clear()
	waves.clear()
	p_pos = Vector2(CX, FLOOR_Y)
	p_vel = Vector2.ZERO
	p_hp = P_HP_MAX
	p_inv_t = 0.0
	p_hurt_t = 0.0
	grease_t = 2.5
	_banner("STAGE %d" % (s + 1), String(STAGES[s]["name"]), 2.2)


func _banner(a: String, b: String = "", d: float = 2.0) -> void:
	banner = a
	banner_sub = b
	banner_t = d


func _play(n: String, vol := 0.0, pitch := 1.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = sfx[n]
	p.volume_db = vol
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# ==================================================================
# 遊戲邏輯
# ==================================================================
func _update_play(dt: float) -> void:
	var S: Dictionary = STAGES[stage]
	spin += float(S["spin"]) * dt * (0.4 if core_phase else 1.0)
	_update_player(dt)

	if state != "play":
		return
	if not core_phase:
		_grow_meat(dt)
		var total := _total_meat()
		if total < NCOL * NROW * MEAT_MAX * 0.02:
			if total > 0.0:
				for c in NCOL:
					for r in NROW:
						var i := c * NROW + r
						if meat[i] > 0.0:
							meat[i] = 0.0
							var a := _wrap((c + 0.5) * STEP + spin - phi)
							if cos(a) > 0.0:
								for k in 4:
									_particle(_pp(R_CORE + 10.0, a, (_row_y(r) + _row_y(r + 1)) * 0.5), Vector2(randf_range(-60, 60), randf_range(-200, -60)), Color(0.2, 0.15, 0.12), 4.0, 0.8)
			_enter_core()
	else:
		core_t -= dt
		wave_t -= dt
		if wave_t <= 0.0:
			wave_t = 2.4 - stage * 0.3
			waves.append({"x": CX - R_CORE, "dir": -1.0})
			waves.append({"x": CX + R_CORE, "dir": 1.0})
			_play("splat", -4.0, 0.6)
		if core_t <= 0.0:
			core_phase = false
			waves.clear()
			for i in meat.size():
				meat[i] = 35.0
			_banner("肉又長回來了！", "沙威核在保護自己……再砍一次！", 2.2)
			shake = 6.0

	# 震波
	for w in waves:
		w["x"] += float(w["dir"]) * 330.0 * dt
		if p_pos.y > FLOOR_Y - 24.0 and absf(float(w["x"]) - p_pos.x) < 20.0:
			_hurt(3.0, float(w["x"]) - float(w["dir"]) * 10.0)
	waves = waves.filter(func(w): return float(w["x"]) > -40.0 and float(w["x"]) < W + 40.0)

	# 熱油滴
	grease_t -= dt
	if grease_t <= 0.0:
		grease_t = float(S["grease"]) * randf_range(0.7, 1.3)
		drops.append({"x": CX + randf_range(-125, 125), "y": CYL_TOP - 4.0, "vy": 0.0, "warn": 0.7})
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
				_particle(Vector2(dp.x, FLOOR_Y), Vector2(randf_range(-120, 120), randf_range(-200, -60)), Color(1.0, 0.8, 0.25), 3.0, 0.4)
			_play("splat", -10.0, randf_range(0.9, 1.2))
	drops = drops.filter(func(d): return not d.has("dead"))


func _grow_meat(dt: float) -> void:
	if core_phase:
		return
	var S: Dictionary = STAGES[stage]
	var g := float(S["growth"])
	var seed_delay := float(S["seed"])
	for c in NCOL:
		var cl := ((c - 1 + NCOL) % NCOL) * NROW
		var cr := ((c + 1) % NCOL) * NROW
		for r in NROW:
			var i := c * NROW + r
			if meat[i] > 0.0:
				meat[i] = minf(MEAT_MAX, meat[i] + g * dt)
			else:
				# 空格：旁邊有厚肉的話，過一陣子會再長出肉芽
				var nb := maxf(maxf(meat[cl + r], meat[cr + r]), maxf(meat[c * NROW + maxi(r - 1, 0)], meat[c * NROW + mini(r + 1, NROW - 1)]))
				if nb > 60.0:
					seed_t[i] += dt
					if seed_t[i] > seed_delay:
						meat[i] = 4.0
						seed_t[i] = 0.0
				else:
					seed_t[i] = 0.0


func _total_meat() -> float:
	var s := 0.0
	for m in meat:
		s += m
	return s


func _face_meat(f: int) -> float:
	var s := 0.0
	for c in range(f * COLS_PER_FACE, (f + 1) * COLS_PER_FACE):
		for r in NROW:
			s += meat[c * NROW + r]
	return s / (COLS_PER_FACE * NROW * MEAT_MAX)


func _enter_core() -> void:
	var S: Dictionary = STAGES[stage]
	core_phase = true
	core_t = float(S["core_time"])
	core_hp = int(S["core_hp"])
	core_hp_max = core_hp
	wave_t = 1.6
	shake = 8.0
	_banner("沙威核 露出了！", "趁肉長回來之前破壞它！", 2.0)
	_play("core", 0.0, 0.7)


func _core_destroyed() -> void:
	core_phase = false
	waves.clear()
	drops.clear()
	state = "clear"
	state_t = 0.0
	total_time += stage_time
	shake = 14.0
	hitstop = 0.25
	_play("boom", 2.0)
	var c := Vector2(CX, (CYL_TOP + CYL_BOT) * 0.5)
	for k in 80:
		var a := randf() * TAU
		var sp := randf_range(100, 520)
		var col := Color(1.0, randf_range(0.4, 0.9), 0.2) if k % 2 == 0 else Color(0.6, 0.3, 0.12)
		_particle(c + Vector2(randf_range(-40, 40), randf_range(-120, 120)), Vector2(cos(a), sin(a)) * sp, col, randf_range(3, 8), randf_range(0.6, 1.4))
	_banner("STAGE CLEAR!", "時間 %s" % _fmt_time(stage_time), 3.4)


func _hurt(dmg: float, from_x: float) -> void:
	if p_inv_t > 0.0 or state != "play":
		return
	p_hp -= dmg
	p_inv_t = 1.1
	p_hurt_t = 0.3
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
			ghosts.append({"p": p_pos, "k": "dash", "f": p_face, "life": 0.25})
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
				_particle(p_pos, Vector2(cos(a) * 140, sin(a) * 40), Color(0.6, 1.0, 0.7), 3.0, 0.25)
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

	# 走到邊緣 → 改成轉動沙威瑪（視角繞著它走）
	var nx := p_pos.x + p_vel.x * dt
	var lo := CX - ZONE
	var hi := CX + ZONE
	if nx > hi:
		phi += (nx - hi) / R_MAX
		nx = hi
	elif nx < lo:
		phi -= (lo - nx) / R_MAX
		nx = lo
	p_pos.x = nx

	if control and state == "play":
		var pressed := Input.is_action_just_pressed("attack")
		if (pressed and p_attack_cd <= 0.0) or (Input.is_action_pressed("attack") and p_attack_cd <= -0.1):
			_do_attack()


func _do_attack() -> void:
	p_combo = (p_combo % 3) + 1 if p_combo_t > 0.0 else 1
	p_combo_t = 0.5
	p_attack_t = 0.2
	p_attack_cd = 0.16
	p_up_slash = Input.is_action_pressed("up")
	var big := p_combo == 3
	var rect: Rect2
	if p_up_slash:
		rect = Rect2(p_pos.x - 60, p_pos.y - 235, 120, 180)
		arcs.append({"c": p_pos + Vector2(0, -120), "r": 72.0, "a0": PI + 0.25, "a1": TAU - 0.25, "life": 0.18, "big": big})
	else:
		var w := 160.0 if big else 125.0
		var h := 145.0 if big else 112.0
		var x0 := p_pos.x - 15.0 if p_face > 0 else p_pos.x + 15.0 - w
		rect = Rect2(x0, p_pos.y - h - 4.0, w, h)
		if big:
			var c := p_pos + Vector2(p_face * 25.0, -60.0)
			if p_face > 0:
				arcs.append({"c": c, "r": 85.0, "a0": -1.4, "a1": 1.2, "life": 0.2, "big": true})
			else:
				arcs.append({"c": c, "r": 85.0, "a0": PI - 1.2, "a1": PI + 1.4, "life": 0.2, "big": true})
	var dmg := SLASH_DMG * (1.8 if big else 1.0)
	var hits := _hit_meat(rect, dmg)
	var core_rect := Rect2(CX - R_CORE * 0.85, CYL_TOP, R_CORE * 1.7, CYL_BOT - CYL_TOP)
	if core_phase and rect.intersects(core_rect):
		core_hp -= 2 if big else 1
		core_flash = 0.1
		hitstop = 0.05
		shake = 5.0
		_play("core", -2.0, randf_range(0.9, 1.1))
		var hp := rect.intersection(core_rect).get_center()
		for k in 10:
			_particle(hp, Vector2(randf_range(-260, 260), randf_range(-260, 100)), Color(1, 0.9, 0.4), 3.0, 0.35)
		if core_hp <= 0:
			_core_destroyed()
	if hits > 0:
		hitstop = 0.045 if big else 0.03
		shake = maxf(shake, 5.0 if big else 2.5)
		if hit_sfx_cd <= 0.0:
			_play("hit", -2.0, randf_range(0.85, 1.15))
			hit_sfx_cd = 0.05
	_play("slash", -5.0, 0.85 if big else randf_range(1.0, 1.2))


func _hit_meat(rect: Rect2, dmg: float) -> int:
	var n := 0
	for c in NCOL:
		var a0 := _wrap(c * STEP + spin - phi)
		var cm := cos(a0 + STEP * 0.5)
		if cm < 0.2:
			continue
		for r in NROW:
			var i := c * NROW + r
			if meat[i] <= 0.0:
				continue
			var rad := _radius(meat[i])
			var xa := CX + rad * sin(a0)
			var xb := CX + rad * sin(a0 + STEP)
			var yo := ELL * rad * cm
			var cell := Rect2(minf(xa, xb), _row_y(r) + yo, absf(xb - xa), _row_y(r + 1) - _row_y(r))
			if cell.intersects(rect):
				meat[i] = maxf(0.0, meat[i] - dmg * (0.55 + 0.45 * cm))
				if meat[i] < 1.0:
					meat[i] = 0.0
				flash[i] = 0.06
				n += 1
				var cc := cell.get_center()
				for k in 3:
					var col := Color(0.62, 0.3, 0.12).lerp(Color(0.95, 0.6, 0.45), randf())
					_particle(cc, Vector2(randf_range(-80, 80) + p_face * 160.0, randf_range(-320, -80)), col, randf_range(3, 6), randf_range(0.5, 0.9))
	return n


# ------------------------------------------------------------------
# 特效
# ------------------------------------------------------------------
func _particle(p: Vector2, v: Vector2, col: Color, size: float, life: float) -> void:
	if particles.size() > 400:
		return
	particles.append({"p": p, "v": v, "c": col, "s": size, "life": life, "max": life})


func _update_fx(dt: float) -> void:
	for p in particles:
		p["v"] = Vector2(p["v"]) + Vector2(0, 900.0 * dt)
		p["p"] = Vector2(p["p"]) + Vector2(p["v"]) * dt
		p["life"] = float(p["life"]) - dt
		if Vector2(p["p"]).y > FLOOR_Y + 6.0:
			p["p"] = Vector2(Vector2(p["p"]).x, FLOOR_Y + 6.0)
			p["v"] = Vector2(Vector2(p["v"]).x * 0.5, -Vector2(p["v"]).y * 0.3)
	particles = particles.filter(func(p): return float(p["life"]) > 0.0)
	for g in ghosts:
		g["life"] = float(g["life"]) - dt
	ghosts = ghosts.filter(func(g): return float(g["life"]) > 0.0)
	for a in arcs:
		a["life"] = float(a["life"]) - dt
	arcs = arcs.filter(func(a): return float(a["life"]) > 0.0)
	for i in flash.size():
		if flash[i] > 0.0:
			flash[i] -= dt
	core_flash -= dt


func _update_player_sprite() -> void:
	var key := "idle"
	if state == "gameover":
		key = "die"
	elif p_attack_t > 0.0:
		key = "jump" if p_up_slash else "slash"
	elif p_dash_t > 0.0:
		key = "dash"
	elif not p_floor:
		key = "jump"
	var tx: Texture2D = tex[key]
	var info: Dictionary = SPR[key]
	player_spr.texture = tx
	player_spr.flip_h = p_face < 0
	var ax := float(info["ax"]) if p_face > 0 else 1.0 - float(info["ax"])
	player_spr.offset = Vector2(-ax * tx.get_width(), -float(info["ay"]) * tx.get_height())
	player_spr.position = p_pos
	if key == "idle" and p_floor and absf(p_vel.x) > 1.0:
		player_spr.position.y -= absf(sin(t * 14.0)) * 4.0
	var blink := p_inv_t > 0.0 and int(t * 20.0) % 2 == 0 and state == "play"
	player_spr.modulate = Color(1, 0.55, 0.55) if p_hurt_t > 0.0 else Color(1, 1, 1, 0.35 if blink else 1.0)


func _bot(dt: float) -> void:
	bot_t += dt
	log_t += dt
	if log_t >= 5.0 and not OS.has_feature("web"):
		log_t = 0.0
		print("[bot] %s stage=%d t=%.0f meat=%.1f%% hp=%.0f core=%s core_hp=%d x=%.0f y=%.0f phi=%.2f cd=%.2f" % [state, stage + 1, stage_time, _total_meat() / (NCOL * NROW * MEAT_MAX) * 100.0, p_hp, core_phase, core_hp, p_pos.x, p_pos.y, phi, p_attack_cd])
	if state == "title" or state == "gameover" or state == "ending":
		if state == "ending" and not OS.has_feature("web"):
			print("[bot] ENDING total=%.1f" % total_time)
			get_tree().quit()
		tap = true
		return
	Input.action_press("attack")
	var want := 0.0
	var high := false
	if core_phase:
		want = signf(CX - p_pos.x) if absf(CX - p_pos.x) > 40.0 else 0.0
		high = fmod(bot_t, 2.4) > 1.2
	else:
		# 鎖定一面砍到乾淨，再換最近的有肉的面；面裡面找肉最多的那一條瞄準
		if bot_face < 0 or _face_meat(bot_face) <= 0.0:
			var bestd := 99.0
			for f in 6:
				if _face_meat(f) > 0.0:
					var d := absf(_wrap((f + 0.5) * COLS_PER_FACE * STEP + spin - phi))
					if d < bestd:
						bestd = d
						bot_face = f
		var tc := bot_face * COLS_PER_FACE
		var tm := -1.0
		for c in range(bot_face * COLS_PER_FACE, (bot_face + 1) * COLS_PER_FACE):
			var cmt := 0.0
			for r in NROW:
				cmt += meat[c * NROW + r]
			if cmt > tm:
				tm = cmt
				tc = c
		var bd := _wrap((tc + 0.5) * STEP + spin - phi)
		var tx := CX + R_MAX * sin(bd)
		if absf(bd) > 0.35:
			want = signf(bd)
		elif absf(tx - p_pos.x) > 12.0:
			want = signf(tx - p_pos.x)
		elif fmod(bot_t, 0.6) < 0.05:
			want = -float(p_face)
		for r in 3:
			if meat[tc * NROW + r] > 0.0:
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
			pass  # 上升中：按住
		elif Input.is_action_pressed("jump"):
			Input.action_release("jump")
		elif p_floor or p_jumps > 0:
			Input.action_press("jump")
	else:
		Input.action_release("up")
		Input.action_release("jump")


# ==================================================================
# 繪圖工具
# ==================================================================
func _wrap(a: float) -> float:
	return fposmod(a + PI, TAU) - PI


func _radius(m: float) -> float:
	return R_CORE + (R_MAX - R_CORE) * m / MEAT_MAX


func _row_y(r: int) -> float:
	return CYL_TOP + (CYL_BOT - CYL_TOP) * r / NROW


## 圓柱表面上的點 → 螢幕座標 (偽 3D 的關鍵就這一行)
func _pp(rad: float, a: float, y: float) -> Vector2:
	return Vector2(CX + rad * sin(a), y + ELL * rad * cos(a))


func _quad(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	ci.draw_primitive(PackedVector2Array([a, b, c, d]), PackedColorArray([col, col, col, col]), PackedVector2Array())


func _quad_grad(ci: CanvasItem, a: Vector2, b: Vector2, c: Vector2, d: Vector2, ct: Color, cb: Color) -> void:
	ci.draw_primitive(PackedVector2Array([a, b, c, d]), PackedColorArray([ct, ct, cb, cb]), PackedVector2Array())


func _ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 40:
		var a := TAU * k / 40.0
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
	# 遠景大樓 (視差，跟著視角轉)
	var span := 26 * 74.0
	var off := fposmod(-phi * 70.0, span)
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
	# 霓虹招牌
	var nx := fposmod(220.0 - phi * 110.0, 1400.0) - 220.0
	var glow := 0.75 + 0.25 * sin(t * 9.0) * (1.0 if fmod(t, 4.0) < 3.6 else 0.0)
	ci.draw_rect(Rect2(nx - 6, 150, 182, 56), Color(0.08, 0.02, 0.1))
	_text(ci, "SHAWARMA", nx + 85, 190, 30, Color(1.0, 0.35, 0.7, glow), 10, Color(1.0, 0.2, 0.6, 0.25 * glow))
	# 廚房後牆磁磚
	var wall_top := 300.0
	_quad_grad(ci, Vector2(-20, wall_top), Vector2(W + 20, wall_top), Vector2(W + 20, FLOOR_Y), Vector2(-20, FLOOR_Y), Color(0.2, 0.17, 0.24), Color(0.13, 0.1, 0.16))
	var toff := fposmod(-phi * 120.0, 48.0)
	for x in range(-48, int(W) + 48, 48):
		ci.draw_line(Vector2(x + toff, wall_top), Vector2(x + toff, FLOOR_Y), Color(0, 0, 0, 0.25), 2)
	for y in range(int(wall_top), int(FLOOR_Y), 24):
		ci.draw_line(Vector2(0, y), Vector2(W, y), Color(0, 0, 0, 0.25), 2)
	ci.draw_rect(Rect2(-20, wall_top - 8, W + 40, 10), Color(0.55, 0.57, 0.62))
	# 烤爐加熱板 (在沙威瑪後方發光)
	var hx := CX - 190.0
	ci.draw_rect(Rect2(hx, CYL_TOP - 34, 380, CYL_BOT - CYL_TOP + 52), Color(0.16, 0.16, 0.2))
	ci.draw_rect(Rect2(hx + 8, CYL_TOP - 26, 364, CYL_BOT - CYL_TOP + 36), Color(0.08, 0.06, 0.08))
	for k in 9:
		var y := CYL_TOP - 14.0 + k * 42.0
		var fl := 0.75 + 0.25 * sin(t * 6.0 + k * 1.7)
		ci.draw_rect(Rect2(hx + 16, y, 348, 16), Color(1.0, 0.35, 0.05, 0.35 * fl))
		ci.draw_rect(Rect2(hx + 16, y + 4, 348, 8), Color(1.0, 0.65, 0.2, 0.9 * fl))
	# 地板 (金屬格子，透視線跟著轉)
	_quad_grad(ci, Vector2(-20, FLOOR_Y), Vector2(W + 20, FLOOR_Y), Vector2(W + 20, H + 20), Vector2(-20, H + 20), Color(0.32, 0.3, 0.36), Color(0.12, 0.1, 0.14))
	ci.draw_line(Vector2(0, FLOOR_Y), Vector2(W, FLOOR_Y), Color(0.75, 0.75, 0.82), 2)
	var foff := fposmod(-phi * 150.0, 80.0)
	for k in range(-8, 9):
		var x0 := CX + k * 80.0 + foff
		ci.draw_line(Vector2(x0, FLOOR_Y), Vector2(CX + (x0 - CX) * 1.9, H), Color(0, 0, 0, 0.3), 2)
	for y in [FLOOR_Y + 18.0, FLOOR_Y + 42.0]:
		ci.draw_line(Vector2(0, y), Vector2(W, y), Color(0, 0, 0, 0.25), 2)


# ------------------------------------------------------------------
# 沙威瑪本體
# ------------------------------------------------------------------
func _draw_shawarma(ci: CanvasItem) -> void:
	# 底盤 + 頂端烤叉
	_ellipse(ci, Vector2(CX, CYL_BOT + 10), R_MAX + 24, (R_MAX + 24) * ELL + 4, Color(0, 0, 0, 0.35))
	_ellipse(ci, Vector2(CX, CYL_BOT + 6), R_MAX + 18, (R_MAX + 18) * ELL, Color(0.24, 0.25, 0.3))
	_ellipse(ci, Vector2(CX, CYL_BOT + 1), R_MAX + 14, (R_MAX + 14) * ELL, Color(0.52, 0.54, 0.6))
	ci.draw_rect(Rect2(CX - 6, CYL_TOP - 70, 12, 80), Color(0.5, 0.52, 0.58))
	ci.draw_rect(Rect2(CX - 6, CYL_TOP - 70, 4, 80), Color(0.85, 0.87, 0.92))
	_ellipse(ci, Vector2(CX, CYL_TOP - 70), 14, 5, Color(0.75, 0.77, 0.82))

	# 由後往前排序 (畫家演算法)
	var order: Array = []
	for c in NCOL:
		var a0 := _wrap(c * STEP + spin - phi)
		order.append([cos(a0 + STEP * 0.5), c, a0])
	order.sort_custom(func(x, y): return x[0] < y[0])

	# 頂面 (肉的上方)
	var capc := Vector2(CX, CYL_TOP)
	var capcol := PackedColorArray([Color(0.42, 0.2, 0.08)])
	for c in NCOL:
		var a0 := c * STEP + spin - phi
		var r0 := _radius(meat[c * NROW]) if meat[c * NROW] > 0.0 else R_CORE
		ci.draw_primitive(PackedVector2Array([capc, _pp(r0, a0, CYL_TOP), _pp(r0, a0 + STEP, CYL_TOP)]), capcol, PackedVector2Array())
	_ellipse(ci, Vector2(CX, CYL_TOP), R_CORE * 0.9, R_CORE * 0.9 * ELL, Color(0.5, 0.25, 0.1))
	_ellipse(ci, Vector2(CX, CYL_TOP), 10, 4, Color(0.15, 0.12, 0.14))

	var pulse := 0.5 + 0.5 * sin(t * (10.0 if core_phase else 3.0))
	for item in order:
		var cm: float = item[0]
		if cm < -0.3:
			continue
		var c: int = item[1]
		var a0: float = item[2]
		var a1 := a0 + STEP
		var am := a0 + STEP * 0.5
		var light := 0.36 + 0.64 * clampf(cos(am + 0.45), 0.0, 1.0)
		var rim := pow(clampf(1.0 - absf(cm), 0.0, 1.0), 3.0) * 0.55

		# 沙威核 (金屬柱 + 發光紋路)
		var core_col := Color(0.3, 0.27, 0.33) * light
		core_col.a = 1.0
		if core_phase:
			core_col = core_col.lerp(Color(1.0, 0.45, 0.15), 0.35 + 0.3 * pulse)
			if core_flash > 0.0:
				core_col = Color(1, 1, 1)
		_quad(ci, _pp(R_CORE, a0, CYL_TOP), _pp(R_CORE, a1, CYL_TOP), _pp(R_CORE, a1, CYL_BOT), _pp(R_CORE, a0, CYL_BOT), core_col)
		if cm > 0.0 and c % 2 == 0:
			var gl := Color(1.0, 0.6, 0.15, (0.35 + 0.5 * pulse) * cm)
			ci.draw_line(_pp(R_CORE, am, CYL_TOP + 6), _pp(R_CORE, am, CYL_BOT - 6), gl, 3.0)

		for r in NROW:
			var i := c * NROW + r
			var m := meat[i]
			var yt := _row_y(r)
			var yb := _row_y(r + 1)
			if m <= 0.0:
				if seed_t[i] > 0.0 and cm > 0.0:
					var sp := seed_t[i] / float(STAGES[stage]["seed"])
					var sc := Color(1.0, 0.55, 0.55, 0.25 + 0.5 * sp)
					var ym := (yt + yb) * 0.5
					_quad(ci, _pp(R_CORE + 2, a0 + STEP * 0.2, ym - 8 * sp), _pp(R_CORE + 2, a1 - STEP * 0.2, ym - 8 * sp), _pp(R_CORE + 2, a1 - STEP * 0.2, ym + 8 * sp), _pp(R_CORE + 2, a0 + STEP * 0.2, ym + 8 * sp), sc)
				continue
			var rad := _radius(m)
			var tt := m / MEAT_MAX
			var base := Color(0.95, 0.62, 0.5).lerp(Color(0.62, 0.3, 0.12), tt)
			base = base.lerp(Color(0.35, 0.15, 0.05), cell_rand[i] * 0.3)
			var col := Color(minf(1.0, base.r * light + rim), minf(1.0, base.g * light + rim * 0.45), base.b * light, 1.0)
			if flash[i] > 0.0:
				col = col.lerp(Color(1, 0.95, 0.85), 0.45)
			# 上方那格比較薄 → 露出這格的頂面
			if r > 0:
				var ra := _radius(meat[i - 1]) if meat[i - 1] > 0.0 else R_CORE
				if ra < rad - 0.5:
					_quad(ci, _pp(ra, a0, yt), _pp(ra, a1, yt), _pp(rad, a1, yt), _pp(rad, a0, yt), col.lightened(0.18))
			# 旁邊那格比較薄 → 露出側面
			var nc := (c + 1) % NCOL if am < 0.0 else (c - 1 + NCOL) % NCOL
			var sa := a1 if am < 0.0 else a0
			var nm := meat[nc * NROW + r]
			var rn := _radius(nm) if nm > 0.0 else R_CORE
			if rn < rad - 0.5:
				_quad(ci, _pp(rn, sa, yt), _pp(rad, sa, yt), _pp(rad, sa, yb), _pp(rn, sa, yb), col.darkened(0.35))
			# 正面
			_quad(ci, _pp(rad, a0, yt), _pp(rad, a1, yt), _pp(rad, a1, yb), _pp(rad, a0, yb), col)
			if cm > 0.1:
				var mark := col.darkened(0.45)
				for k in 2:
					var fy := yt + (yb - yt) * (0.3 + 0.4 * k + (cell_rand[i] - 0.5) * 0.15)
					ci.draw_line(_pp(rad, a0 + STEP * 0.12, fy), _pp(rad, a1 - STEP * 0.12, fy + 4.0 * (cell_rand[i] - 0.5)), mark, 2.0)
				ci.draw_line(_pp(rad, a0, yt), _pp(rad, a1, yt), col.lightened(0.25), 1.5)

	# 沙威核露出時的「眼睛」
	if core_phase:
		var ec := Vector2(CX, (CYL_TOP + CYL_BOT) * 0.5 + ELL * R_CORE)
		_ellipse(ci, ec, 46, 30, Color(0.1, 0.02, 0.02))
		_ellipse(ci, ec, 40, 24, Color(1, 0.95, 0.8) if core_flash <= 0.0 else Color(1, 0.3, 0.3))
		var look := clampf((p_pos.x - CX) / 200.0, -1.0, 1.0)
		var iris := ec + Vector2(look * 20.0, clampf((p_pos.y - 60 - ec.y) / 200.0, -1, 1) * 8.0)
		_ellipse(ci, iris, 15, 15, Color(0.85, 0.1, 0.05))
		_ellipse(ci, iris, 6, 9, Color(0.05, 0, 0))
		ci.draw_line(ec + Vector2(-46, -40), ec + Vector2(-8, -28), Color(0.1, 0.02, 0.02), 6)
		ci.draw_line(ec + Vector2(46, -40), ec + Vector2(8, -28), Color(0.1, 0.02, 0.02), 6)


# ------------------------------------------------------------------
# 特效層
# ------------------------------------------------------------------
func _draw_fx_back(ci: CanvasItem) -> void:
	# 殘影
	for g in ghosts:
		var tx: Texture2D = tex[g["k"]]
		var info: Dictionary = SPR[g["k"]]
		var f := float(g["f"])
		ci.draw_set_transform(Vector2(g["p"]), 0.0, Vector2(0.5 * f, 0.5))
		ci.draw_texture(tx, Vector2(-float(info["ax"]) * tx.get_width(), -float(info["ay"]) * tx.get_height()), Color(0.3, 1.0, 0.6, float(g["life"]) * 2.4))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 熱油
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
	# 地面震波
	for w in waves:
		var x := float(w["x"])
		for k in 3:
			var hh := 46.0 - k * 12.0
			ci.draw_line(Vector2(x - float(w["dir"]) * k * 8.0, FLOOR_Y), Vector2(x - float(w["dir"]) * k * 8.0, FLOOR_Y - hh), Color(1.0, 0.5 + k * 0.2, 0.15, 0.9 - k * 0.25), 7.0 - k * 2.0)


func _draw_fx_front(ci: CanvasItem) -> void:
	for a in arcs:
		var al := float(a["life"]) / 0.2
		var w := 16.0 if a["big"] else 10.0
		ci.draw_arc(Vector2(a["c"]), float(a["r"]), float(a["a0"]), float(a["a1"]), 24, Color(0.4, 1.0, 0.55, 0.5 * al), w + 10.0)
		ci.draw_arc(Vector2(a["c"]), float(a["r"]), float(a["a0"]), float(a["a1"]), 24, Color(0.85, 1.0, 0.9, al), w)
	for p in particles:
		var s := float(p["s"])
		var c: Color = p["c"]
		c.a = clampf(float(p["life"]) / float(p["max"]) * 2.0, 0.0, 1.0)
		ci.draw_rect(Rect2(Vector2(p["p"]) - Vector2(s, s) * 0.5, Vector2(s, s)), c)


# ------------------------------------------------------------------
# HUD
# ------------------------------------------------------------------
func _fmt_time(sec: float) -> String:
	return "%d:%04.1f" % [int(sec) / 60, fmod(sec, 60.0)]


func _draw_hud(ci: CanvasItem) -> void:
	if state == "title":
		_draw_title(ci)
		return
	# HP 條 (洛克人風格直條)
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
	var head: Texture2D = tex["idle"]
	ci.draw_texture_rect_region(head, Rect2(hx - 12, hy + segs * 8 + 8, 42, 42), Rect2(head.get_width() * 0.28, 0, head.get_width() * 0.5, head.get_width() * 0.5))

	# 上方資訊
	var S: Dictionary = STAGES[stage]
	_text(ci, "STAGE %d  %s" % [stage + 1, S["name"]], 300, 30, 18, Color(1, 1, 1), 4)
	_text(ci, _fmt_time(stage_time), 660, 30, 18, Color(0.8, 1, 0.9), 4)
	var bx := 320.0
	var by := 42.0
	var bw := 320.0
	ci.draw_rect(Rect2(bx - 3, by - 3, bw + 6, 20), Color(0, 0, 0, 0.75))
	if core_phase:
		var f := float(core_hp) / float(core_hp_max)
		ci.draw_rect(Rect2(bx, by, bw * f, 14), Color(1.0, 0.3, 0.15).lerp(Color(1, 1, 0.5), 0.5 + 0.5 * sin(t * 12)))
		_text(ci, "沙威核", bx - 44, by + 14, 16, Color(1, 0.6, 0.4), 4)
		_text(ci, "肉再生倒數 %.1f" % maxf(0.0, core_t), CX, by + 40, 18, Color(1, 0.85, 0.3) if core_t > 3 else Color(1, 0.3, 0.3), 5)
	else:
		var f := _total_meat() / (NCOL * NROW * MEAT_MAX)
		ci.draw_rect(Rect2(bx, by, bw * f, 14), Color(0.75, 0.38, 0.15))
		ci.draw_rect(Rect2(bx, by, bw * f, 4), Color(0.95, 0.6, 0.4))
		_text(ci, "肉量", bx - 30, by + 14, 16, Color(1, 0.8, 0.6), 4)
		_text(ci, "%d%%" % int(ceil(f * 100.0)), bx + bw + 28, by + 14, 16, Color(1, 1, 1), 4)

	_draw_minimap(ci)

	if stage == 0 and state == "play" and state_t < 9.0 and not DisplayServer.is_touchscreen_available():
		_text(ci, "←→ 移動 (走到邊緣會轉動沙威瑪)   Z 跳(可二段跳)   X 斬(連打!)   C 衝刺   ↑+X 上斬", CX, 528, 14, Color(1, 1, 1, clampf(9.0 - state_t, 0, 1)), 4)

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
			_text(ci, "按 X / Enter 或點擊畫面 重新挑戰", CX, 310, 20, Color(1, 1, 0.6, 0.6 + 0.4 * sin(t * 6)), 5)
	elif state == "ending":
		ci.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, clampf(state_t * 0.5, 0, 0.65)))
		_text(ci, "全部沙威瑪 斬殺完成！", CX, 190, 46, Color(1, 0.9, 0.3), 10)
		_text(ci, "總時間 %s" % _fmt_time(total_time), CX, 240, 26, Color(1, 1, 1), 6)
		_text(ci, "柯基英雄拯救了夜市……今晚吃沙威瑪捲餅！", CX, 280, 22, Color(0.8, 1, 0.9), 5)
		if state_t > 2.0:
			_text(ci, "按 X / Enter 或點擊畫面 回到標題", CX, 340, 20, Color(1, 1, 0.6, 0.6 + 0.4 * sin(t * 6)), 5)


func _draw_minimap(ci: CanvasItem) -> void:
	# 六面小地圖：下方 = 目前面向你的那一面
	var mc := Vector2(892, 92)
	var mr := 50.0
	ci.draw_circle(mc, mr + 10, Color(0, 0, 0, 0.55))
	for f in 6:
		var b0 := f * COLS_PER_FACE * STEP + spin - phi
		var b1 := b0 + COLS_PER_FACE * STEP
		var p0 := mc + mr * Vector2(sin(b0), cos(b0) * 0.8)
		var p1 := mc + mr * Vector2(sin(b1), cos(b1) * 0.8)
		var fm := _face_meat(f)
		var col := Color(0.25, 0.22, 0.3).lerp(Color(0.85, 0.42, 0.16), fm)
		if fm <= 0.0:
			col = Color(0.3, 0.8, 0.45) if not core_phase else Color(1, 0.5, 0.2)
		ci.draw_colored_polygon(PackedVector2Array([mc, p0, p1]), col)
		ci.draw_line(p0, p1, Color(1, 1, 1, 0.8), 2)
		ci.draw_line(mc, p0, Color(0, 0, 0, 0.5), 1)
		var lc := (mc + p0 + p1) / 3.0
		_text(ci, str(f + 1), lc.x, lc.y + 6, 15, Color(1, 1, 1), 3)
	var pm := mc + Vector2(0, mr * 0.8 + 14)
	ci.draw_colored_polygon(PackedVector2Array([pm + Vector2(0, -8), pm + Vector2(-7, 4), pm + Vector2(7, 4)]), Color(0.4, 1, 0.6))
	_text(ci, "六面圖", mc.x, mc.y - mr - 6, 13, Color(1, 1, 1, 0.8), 3)


func _draw_title(ci: CanvasItem) -> void:
	ci.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.35))
	_text(ci, "奇異果英雄傳 外傳", CX + 120, 120, 24, Color(0.7, 1, 0.75), 6)
	_text(ci, "沙威瑪斬", CX + 120, 196, 84, Color(1.0, 0.78, 0.25), 14, Color(0.35, 0.08, 0.0))
	_text(ci, "SHAWARMA  SLASH", CX + 120, 234, 22, Color(1, 0.5, 0.3), 6)
	_text(ci, "旋轉的「沙威核」會不停長出肉！", CX + 120, 290, 20, Color(1, 1, 1), 5)
	_text(ci, "砍肉的速度要比長肉更快，把六面的肉全部砍光，", CX + 120, 318, 20, Color(1, 1, 1), 5)
	_text(ci, "再趁肉長回來之前破壞沙威核！", CX + 120, 346, 20, Color(1, 1, 1), 5)
	_text(ci, "按 Enter / X 或點擊畫面 開始", CX + 120, 410, 24, Color(1, 1, 0.5, 0.55 + 0.45 * sin(t * 5)), 6)
	_text(ci, "←→移動  Z跳  X斬  C衝刺  ↑+X上斬   (手機：螢幕按鈕)", CX + 120, 445, 15, Color(0.85, 0.85, 1), 4)
