class_name Shawarma
extends RefCounted
## 一根沙威瑪：肉格子資料、生長、被砍。畫法在 main.gd。
##
## 圓柱切成 NCOL 直條 × nrow 橫列，每格肉量 0~100。
## 肉量決定那格往外凸多少（半徑），fresh 表示「剛長出來還是生的」。

const NCOL := 24
const STEP := TAU / NCOL
const MEAT_MAX := 100.0
const ROW_H := 50.0
const SLICES := 5          # 每一列畫成 5 片薄肉 (像真的沙威瑪一片片疊起來)
const COLS_PER_FACE := 4
const ELL := 0.13

const KINDS := {
	"chicken": {"name": "雞肉沙威瑪", "rows": 4, "r_core": 62.0, "r_max": 110.0, "growth": 3.0, "spin": 0.42,
		"seed": 2.4, "grease": 4.5, "core_hp": 4, "core_time": 5.0, "init": [28.0, 52.0], "tint": Color(1.0, 0.95, 0.78)},
	"beef": {"name": "牛肉沙威瑪", "rows": 5, "r_core": 66.0, "r_max": 120.0, "growth": 3.6, "spin": 0.36,
		"seed": 2.2, "grease": 3.8, "core_hp": 6, "core_time": 5.5, "init": [36.0, 60.0], "tint": Color(0.86, 0.72, 0.68)},
	"spicy": {"name": "辣味沙威瑪", "rows": 4, "r_core": 62.0, "r_max": 114.0, "growth": 3.8, "spin": 0.5,
		"seed": 2.0, "grease": 1.7, "core_hp": 5, "core_time": 5.0, "init": [30.0, 56.0], "tint": Color(1.0, 0.6, 0.48)},
	"boss": {"name": "巨無霸沙威瑪", "rows": 6, "r_core": 86.0, "r_max": 152.0, "growth": 4.2, "spin": 0.3,
		"seed": 2.0, "grease": 2.2, "core_hp": 20, "core_time": 9.0, "init": [60.0, 88.0], "tint": Color(1.0, 0.88, 0.82)},
}

var kind := ""
var title := ""
var nrow := 4
var r_core := 62.0
var r_max := 110.0
var growth := 3.0
var spin_speed := 0.4
var seed_delay := 2.4
var grease := 4.0
var core_hp_max := 4
var core_time_max := 5.0
var tint := Color.WHITE
var is_boss := false

var cx := 480.0
var bot := 452.0
var top := 204.0

var meat := PackedFloat32Array()
var fresh := PackedFloat32Array()   # 1 = 剛長出來的生肉，會慢慢烤熟
var seed_t := PackedFloat32Array()
var flash := PackedFloat32Array()
var bulge := PackedFloat32Array()   # 長肉時「鼓起來」的動畫
var cut := PackedFloat32Array()     # 刀痕
var rnd := PackedFloat32Array()
var spin := 0.0
var core_phase := false
var core_t := 0.0
var core_hp := 0
var core_flash := 0.0
var life_t := 0.0
var drips: Array = []               # 往下流的肉汁 {c, y, v, len}
var drip_t := 0.0
var events: Array = []              # 給 main 做特效用 ["sprout"/"swell"/"drip", c, r]


func setup(k: String, diff: float) -> void:
	kind = k
	var info: Dictionary = KINDS[k]
	title = String(info["name"])
	nrow = int(info["rows"])
	r_core = float(info["r_core"])
	r_max = float(info["r_max"])
	growth = float(info["growth"]) * diff
	spin_speed = float(info["spin"]) * (0.75 + 0.25 * diff)
	seed_delay = float(info["seed"]) / diff
	grease = float(info["grease"]) / diff
	core_hp_max = int(info["core_hp"])
	core_time_max = float(info["core_time"])
	tint = info["tint"]
	is_boss = k == "boss"
	top = bot - nrow * ROW_H
	var n := NCOL * nrow
	for arr in [meat, fresh, seed_t, flash, bulge, cut, rnd]:
		arr.resize(n)
	var lo: float = info["init"][0]
	var hi: float = info["init"][1]
	var off := randf() * TAU
	for c in NCOL:
		for r in nrow:
			var i := c * nrow + r
			var v := lerpf(lo, hi, 0.5 + 0.5 * sin(c * STEP * 2.0 + off + r * 0.6))
			meat[i] = clampf(v + randf_range(-8, 8), 10.0, MEAT_MAX)
			fresh[i] = 0.0
			seed_t[i] = 0.0
			flash[i] = 0.0
			bulge[i] = 0.0
			cut[i] = 0.0
			rnd[i] = randf()
	spin = randf() * TAU
	core_phase = false
	core_hp = core_hp_max


# ---------------- 幾何 ----------------
## 肉的輪廓：上面寬、下面收窄的「蛋形」(像真的沙威瑪)
func profile(y: float) -> float:
	var f := clampf((y - top) / (bot - top), 0.0, 1.0)
	return 0.9 + 0.16 * sin(PI * minf(1.0, f + 0.2)) - 0.2 * f * f


func radius(m: float, r: int = -1) -> float:
	var pr := profile(row_y(r) + ROW_H * 0.5) if r >= 0 else 1.0
	return r_core + (r_max * pr - r_core) * m / MEAT_MAX


## 每一片薄肉邊緣凹凸不平 (固定在肉上，跟著轉)
func slice_jag(c: int, k: int) -> float:
	var h := sin(c * 12.9898 + k * 78.233) * 43758.5453
	return (h - floor(h)) - 0.5


func row_y(r: int) -> float:
	return top + ROW_H * r


func col_angle(c: int, phi: float) -> float:
	return fposmod(c * STEP + spin - phi + PI, TAU) - PI


## 圓柱表面上的點 → 螢幕座標（偽 3D 的關鍵）
func pp(rad: float, a: float, y: float) -> Vector2:
	return Vector2(cx + rad * sin(a), y + ELL * rad * cos(a))


func cell_radius(i: int) -> float:
	return radius(meat[i], i % nrow) + bulge[i] * 7.0 if meat[i] > 0.0 else r_core


# ---------------- 數值 ----------------
func total() -> float:
	var s := 0.0
	for m in meat:
		s += m
	return s


func ratio() -> float:
	return total() / (NCOL * nrow * MEAT_MAX)


func face_meat(f: int) -> float:
	var s := 0.0
	for c in range(f * COLS_PER_FACE, (f + 1) * COLS_PER_FACE):
		for r in nrow:
			s += meat[c * nrow + r]
	return s / (COLS_PER_FACE * nrow * MEAT_MAX)


# ---------------- 更新 ----------------
func update(dt: float) -> void:
	life_t += dt
	spin += spin_speed * dt * (0.4 if core_phase else 1.0)
	core_flash -= dt
	for i in flash.size():
		if flash[i] > 0.0:
			flash[i] -= dt
		if bulge[i] > 0.0:
			bulge[i] = maxf(0.0, bulge[i] - dt * 3.5)
		if cut[i] > 0.0:
			cut[i] -= dt
	_update_drips(dt)
	if core_phase:
		return
	for c in NCOL:
		var cl := ((c - 1 + NCOL) % NCOL) * nrow
		var cr := ((c + 1) % NCOL) * nrow
		for r in nrow:
			var i := c * nrow + r
			var m := meat[i]
			if m > 0.0:
				var nm := minf(MEAT_MAX, m + growth * dt)
				if int(nm / 25.0) > int(m / 25.0):
					bulge[i] = 1.0
					events.append(["swell", c, r])
				meat[i] = nm
				fresh[i] = maxf(0.0, fresh[i] - dt * 0.2)
			else:
				var nb := maxf(maxf(meat[cl + r], meat[cr + r]), maxf(meat[c * nrow + maxi(r - 1, 0)], meat[c * nrow + mini(r + 1, nrow - 1)]))
				if nb > 55.0:
					seed_t[i] += dt
					if seed_t[i] > seed_delay:
						meat[i] = 8.0
						fresh[i] = 1.0
						bulge[i] = 1.0
						seed_t[i] = 0.0
						events.append(["sprout", c, r])
				else:
					seed_t[i] = 0.0


func _update_drips(dt: float) -> void:
	drip_t -= dt
	if drip_t <= 0.0 and not core_phase:
		drip_t = randf_range(0.15, 0.5) / maxf(0.2, ratio() * (2.0 if is_boss else 1.2))
		for k in 4:
			var c := randi() % NCOL
			var r := randi() % nrow
			if meat[c * nrow + r] > 30.0:
				drips.append({"c": c, "y": row_y(r) + randf() * ROW_H * 0.5, "v": 8.0, "len": randf_range(5, 11)})
				break
	for d in drips:
		d["v"] = minf(float(d["v"]) + 45.0 * dt, 75.0)
		d["y"] = float(d["y"]) + float(d["v"]) * dt
		if float(d["y"]) >= bot:
			d["dead"] = true
			events.append(["drip", int(d["c"]), nrow - 1])
	drips = drips.filter(func(d): return not d.has("dead"))


## 砍：rect 是螢幕上的刀光範圍。回傳被砍到的格子中心點
func hit(rect: Rect2, dmg: float, phi: float) -> Array:
	var pts: Array = []
	for c in NCOL:
		var a0 := col_angle(c, phi)
		var cm := cos(a0 + STEP * 0.5)
		if cm < 0.2:
			continue
		for r in nrow:
			var i := c * nrow + r
			if meat[i] <= 0.0:
				continue
			var rad := radius(meat[i], r)
			var xa := cx + rad * sin(a0)
			var xb := cx + rad * sin(a0 + STEP)
			var cell := Rect2(minf(xa, xb), row_y(r) + ELL * rad * cm, absf(xb - xa), ROW_H)
			if cell.intersects(rect):
				var before := meat[i]
				meat[i] = maxf(0.0, meat[i] - dmg * (0.55 + 0.45 * cm))
				if meat[i] < 1.0:
					meat[i] = 0.0
				flash[i] = 0.06
				cut[i] = 0.18
				pts.append([cell.get_center(), before - meat[i], i])
	return pts


func core_rect() -> Rect2:
	return Rect2(cx - r_core * 0.85, top, r_core * 1.7, bot - top)
