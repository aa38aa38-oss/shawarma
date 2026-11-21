#!/usr/bin/env python3
"""產生遊戲素材：裁切主角圖、合成音效與 BGM、按鈕圖。

用法: python3 tools/make_assets.py <kiwi-legend 資料夾路徑>
(字型子集化請用 tools/make_font.py)
"""
import sys, os, wave, math
import numpy as np
from PIL import Image, ImageDraw, ImageFont

SRC = sys.argv[1] if len(sys.argv) > 1 else "../kiwi-legend"
OUT = os.path.join(os.path.dirname(__file__), "..", "game", "assets")
os.makedirs(OUT, exist_ok=True)

# ---------- 主角圖：裁掉透明邊，縮成畫面大小的 2 倍 ----------
# name: (來源檔, 畫面上高度 px)
SPRITES = {
    "idle": ("player.png", 112),
    "jump": ("player-jump.png", 128),
    "slash": ("player-slash.png", 108),
    "dash": ("player-rush.png", 150),
    "die": ("player-die.png", 110),
}
for name, (src, h) in SPRITES.items():
    im = Image.open(os.path.join(SRC, src)).convert("RGBA")
    a = im.split()[3].point(lambda v: 255 if v > 20 else 0)
    im = im.crop(a.getbbox())
    th = h * 2
    tw = round(im.width * th / im.height)
    im = im.resize((tw, th), Image.LANCZOS)
    im.save(os.path.join(OUT, f"hero_{name}.png"))
    print("sprite", name, im.size)

# ---------- 音效 ----------
SR = 22050
rng = np.random.default_rng(7)


def save(name, x, vol=0.9):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) or 1.0
    x = (x / m * vol * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(x.tobytes())
    print("sound", name, len(x) / SR)


def tt(d):
    return np.arange(int(SR * d)) / SR


def lowpass(x, cut):
    """cut: 每個 sample 的截止頻率陣列或常數"""
    cut = np.broadcast_to(np.asarray(cut, dtype=float), x.shape)
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        a = 1 - math.exp(-2 * math.pi * cut[i] / SR)
        acc += a * (x[i] - acc)
        y[i] = acc
    return y


def sweep(f0, f1, d, kind="sin"):
    t = tt(d)
    f = np.linspace(f0, f1, len(t))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) if kind == "sin" else np.sign(np.sin(ph))


t = tt(0.16)
save("sfx_slash.wav", lowpass(rng.uniform(-1, 1, len(t)), np.linspace(6000, 900, len(t))) * np.exp(-t * 18)
     + 0.3 * sweep(2200, 500, 0.16) * np.exp(-t * 25), 0.7)
t = tt(0.14)
save("sfx_hit.wav", sweep(160, 45, 0.14) * np.exp(-t * 22)
     + 0.6 * lowpass(rng.uniform(-1, 1, len(t)), 2500) * np.exp(-t * 35), 0.8)
t = tt(0.13)
save("sfx_jump.wav", 0.5 * sweep(260, 720, 0.13, "sq") * np.exp(-t * 10), 0.45)
t = tt(0.3)
save("sfx_hurt.wav", 0.5 * sweep(520, 120, 0.3, "sq") * (0.6 + 0.4 * np.sin(t * 2 * np.pi * 30)) * np.exp(-t * 6), 0.6)
t = tt(1.0)
save("sfx_boom.wav", lowpass(rng.uniform(-1, 1, len(t)), np.linspace(3000, 150, len(t))) * np.exp(-t * 4)
     + 0.7 * sweep(90, 30, 1.0) * np.exp(-t * 5), 0.95)
t = tt(0.35)
save("sfx_core.wav", sum(np.sin(2 * np.pi * f * t) * np.exp(-t * k) for f, k in [(520, 9), (1385, 12), (2210, 16), (3150, 20)]), 0.6)
t = tt(0.12)
save("sfx_splat.wav", lowpass(rng.uniform(-1, 1, len(t)), 1200) * np.exp(-t * 30), 0.5)
t = tt(0.22)
save("sfx_dash.wav", lowpass(rng.uniform(-1, 1, len(t)), np.linspace(800, 4000, len(t))) * np.sin(np.pi * t / 0.22), 0.45)

# ---------- BGM：A 小調 8-bit 小節循環 ----------
BPM = 150
STEP = 60 / BPM / 4  # 16 分音符


def midi(n):
    return 440 * 2 ** ((n - 69) / 12)


def sq(f, d, duty=0.5):
    t = tt(d)
    return np.where((t * f) % 1 < duty, 1.0, -1.0)


def tri(f, d):
    t = tt(d)
    return 2 * np.abs(2 * ((t * f) % 1) - 1) - 1


A, C, D, E, F, G, Gs, B = 57, 60, 62, 64, 65, 67, 68, 59
roots = [A, F, G, E, A, F, D, E]  # 8 小節
lead_bars = [
    [81, 0, 76, 0, 81, 84, 83, 81, 79, 0, 76, 0, 79, 81, 0, 0],
    [77, 0, 72, 0, 77, 81, 79, 77, 76, 0, 72, 0, 74, 76, 0, 0],
    [79, 0, 74, 0, 79, 83, 81, 79, 77, 0, 74, 0, 77, 79, 0, 0],
    [76, 0, 80, 0, 83, 0, 80, 76, 83, 0, 88, 0, 86, 0, 83, 0],
    [81, 0, 76, 0, 81, 84, 83, 81, 79, 0, 76, 0, 79, 81, 0, 0],
    [77, 0, 81, 0, 84, 0, 81, 77, 89, 0, 88, 0, 84, 0, 81, 0],
    [86, 0, 81, 0, 77, 0, 74, 77, 81, 0, 79, 0, 77, 0, 74, 0],
    [76, 0, 80, 83, 88, 0, 86, 0, 83, 0, 80, 0, 76, 0, 0, 0],
]
n_steps = 16 * len(roots)
L = int(n_steps * STEP * SR)
song = np.zeros(L)
sl = int(STEP * SR)


def put(sig, step, gain):
    s = step * sl
    e = min(L, s + len(sig))
    song[s:e] += sig[: e - s] * gain


for b, root in enumerate(roots):
    for s in range(16):
        st = b * 16 + s
        # bass：八度跳動
        note = root - 12 + (12 if s % 2 else 0)
        env = np.exp(-tt(STEP) * 8)
        put(tri(midi(note), STEP) * env, st, 0.55)
        # lead
        n = lead_bars[b][s]
        if n:
            hold = 1
            while s + hold < 16 and lead_bars[b][s + hold] == 0 and hold < 2:
                hold += 1
            d = STEP * hold
            env = np.minimum(1, tt(d) * 200) * np.exp(-tt(d) * 3)
            put(sq(midi(n), d, 0.25) * env, st, 0.22)
        # 鼓
        if s % 4 == 0:
            put(sweep(150, 40, 0.12) * np.exp(-tt(0.12) * 20), st, 0.9)
        if s % 8 == 4:
            put(lowpass(rng.uniform(-1, 1, int(SR * 0.12)), 3500) * np.exp(-tt(0.12) * 25), st, 0.6)
        if s % 2 == 1:
            put(rng.uniform(-1, 1, int(SR * 0.03)) * np.exp(-tt(0.03) * 120), st, 0.18)
save("bgm.wav", np.tanh(song * 1.2), 0.75)

# ---------- 觸控按鈕圖 ----------
FONT = "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"
for name, label in [("left", "◀"), ("right", "▶"), ("up", "▲"), ("jump", "跳"), ("attack", "斬"), ("dash", "衝")]:
    S = 128
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse((4, 4, S - 4, S - 4), fill=(20, 20, 30, 110), outline=(255, 255, 255, 170), width=5)
    f = ImageFont.truetype(FONT, 58)
    d.text((S / 2, S / 2), label, font=f, fill=(255, 255, 255, 220), anchor="mm")
    im.save(os.path.join(OUT, f"btn_{name}.png"))
print("done")
