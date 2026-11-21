#!/usr/bin/env python3
"""用程式畫「暫代用」的沙威瑪貼圖，放進 art_src/shawarma/。
之後用 Gemini 生的圖直接覆蓋同名檔案即可。

貼圖是沙威瑪表面「攤平」的樣子：左右邊緣必須能無縫接起來（因為會繞一圈）。
"""
import os
import numpy as np
from PIL import Image, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "art_src", "shawarma")
os.makedirs(OUT, exist_ok=True)
W, H = 1024, 400
rng = np.random.default_rng(3)
X, Y = np.meshgrid(np.arange(W), np.arange(H))


def pnoise(octaves, base_k=2, ky_scale=1.0, seed=0):
    """左右循環的雜訊 (x 方向頻率是整數 → 無縫)"""
    r = np.random.default_rng(seed)
    n = np.zeros((H, W))
    amp = 1.0
    for o in range(octaves):
        k = base_k * 2 ** o
        for _ in range(4):
            kx = int(r.integers(k, 2 * k + 1))
            ky = r.uniform(0.5, 1.5) * k * ky_scale * H / W
            ph1, ph2 = r.uniform(0, 2 * np.pi, 2)
            n += amp * np.sin(2 * np.pi * kx * X / W + ph1) * np.sin(2 * np.pi * ky * Y / H + ph2)
        amp *= 0.55
    n -= n.min()
    return n / n.max()


def lerp(a, b, t):
    t = t[..., None]
    return np.asarray(a) * (1 - t) + np.asarray(b) * t


def save(name, rgb):
    im = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8))
    im.save(os.path.join(OUT, name))
    print(name, im.size)


# ---------- 烤熟的肉表面 ----------
warp = pnoise(4, 2, 1, 1)
layers = np.sin((Y + 60 * warp + 14 * pnoise(3, 8, 1, 2)) * 2 * np.pi / 30.0)  # 一片片疊起來的肉
crisp = pnoise(5, 4, 1, 3)
char = pnoise(4, 6, 1, 4)
lump = pnoise(4, 10, 1.5, 11)
base = lerp((0.66, 0.35, 0.14), (0.4, 0.18, 0.07), crisp * 0.6 + lump * 0.4)
ridge = np.clip(layers, 0, 1) ** 2
col = lerp(base, (0.86, 0.56, 0.26), ridge * 0.75)              # 隆起處金黃酥脆
groove = np.clip(-layers, 0, 1) ** 3
col = lerp(col, (0.25, 0.1, 0.03), groove * 0.8)                # 層與層之間的深色縫
col = lerp(col, (0.12, 0.05, 0.02), np.clip((char - 0.8) * 6, 0, 1) * np.clip(layers, 0, 1))  # 焦黑
fat = pnoise(3, 30, 1, 5)
col = lerp(col, (1.0, 0.86, 0.55), np.clip((fat - 0.86) * 9, 0, 1) * ridge)  # 油亮的脂肪
grain = rng.normal(0, 0.035, (H, W, 1))
save("meat_surface.png", col + grain)

# ---------- 剛長出來的生肉 ----------
layers2 = np.sin((Y + 18 * warp) * 2 * np.pi / 13.0)
m = pnoise(4, 3, 1, 7)
col = lerp((0.93, 0.5, 0.48), (0.78, 0.33, 0.33), m)
col = lerp(col, (1.0, 0.88, 0.85), np.clip((pnoise(4, 10, 2, 8) - 0.7) * 4, 0, 1) * 0.8)  # 白色油花
col = lerp(col, (0.6, 0.22, 0.2), np.clip(-layers2, 0, 1) ** 3 * 0.6)
save("meat_raw.png", col + rng.normal(0, 0.03, (H, W, 1)))

# ---------- 沙威核 (金屬 + 發光紋路) ----------
metal = lerp((0.22, 0.2, 0.26), (0.38, 0.36, 0.42), pnoise(3, 2, 4, 9))
bands = (np.abs(((X / W * 24) % 1) - 0.5) < 0.04).astype(float)       # 直的發光線
rings = (np.abs(((Y / H * 6) % 1) - 0.5) > 0.47).astype(float)        # 橫的接縫
rune = np.clip((pnoise(3, 6, 1, 10) - 0.75) * 6, 0, 1) * (np.abs(((X / W * 12) % 1) - 0.5) < 0.18)
glow = np.clip(bands + rune, 0, 1)
col = lerp(metal, (0.12, 0.1, 0.12), rings)
col = lerp(col, (1.0, 0.55, 0.12), glow)
save("core.png", col)
