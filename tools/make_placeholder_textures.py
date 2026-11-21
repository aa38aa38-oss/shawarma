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


# ---------- 烤熟的肉表面 (參考真的雞肉沙威瑪：一片片薄肉疊起來) ----------
# 貼圖高 400px = 遊戲裡 6 列 × 5 片 = 30 片，每片 13.33px，跟遊戲裡的切片對齊
NS = 30
PER = H / NS
warp = pnoise(4, 3, 1, 1)
edge_n = pnoise(4, 12, 1, 2)                       # 每片邊緣凹凸
yy = Y + (edge_n - 0.5) * 9.0 + (pnoise(3, 30, 0.6, 12) - 0.5) * 5.0
band = (yy / PER) % 1.0                            # 0 = 一片的上緣, 1 = 下緣
idx = np.floor(yy / PER)
slice_tone = (np.sin(idx * 12.9898) * 43758.5453) % 1.0   # 每片顏色不同
fiber = pnoise(4, 40, 0.15, 3)                     # 橫向肉纖維
crisp = pnoise(4, 6, 1, 4)
char = pnoise(4, 10, 1, 5)

body = lerp((0.93, 0.8, 0.56), (0.8, 0.6, 0.33), slice_tone * 0.7 + fiber * 0.3)     # 淡金色雞肉
col = body
top_edge = np.clip(1.0 - band / 0.32, 0, 1) ** 1.5                                   # 上緣烤得金黃酥脆
brown = np.clip((crisp - 0.25) * 1.8, 0, 1)
col = lerp(col, (0.66, 0.38, 0.12), np.clip(top_edge * (0.4 + 0.9 * brown) + brown * 0.35, 0, 1))
tip = np.clip(1.0 - band / 0.18, 0, 1)                                              # 最邊邊焦一點
col = lerp(col, (0.42, 0.22, 0.07), tip * np.clip((char - 0.3) * 2.2, 0, 1))
gap = np.clip((band - 0.82) / 0.18, 0, 1) ** 2                                       # 片與片之間的陰影縫
col = lerp(col, (0.3, 0.17, 0.07), gap * 0.85)
col = lerp(col, (0.25, 0.12, 0.04), np.clip((char - 0.72) * 5, 0, 1) * (1 - gap) * 0.8)    # 零星焦黑
gloss = np.clip((pnoise(3, 25, 1, 6) - 0.8) * 6, 0, 1) * (1 - gap)                   # 油亮
col = lerp(col, (1.0, 0.95, 0.8), gloss * 0.6)
col = col * (0.92 + 0.16 * fiber[..., None])
save("meat_surface.png", col + rng.normal(0, 0.025, (H, W, 1)))

# ---------- 剛長出來的生肉 (粉紅、油花) ----------
body = lerp((0.96, 0.62, 0.58), (0.84, 0.4, 0.4), slice_tone * 0.6 + fiber * 0.4)
col = lerp(body, (1.0, 0.9, 0.86), np.clip((pnoise(4, 14, 1.5, 8) - 0.72) * 4, 0, 1) * 0.8)   # 白色油花
col = lerp(col, (0.62, 0.25, 0.24), gap * 0.7)
col = lerp(col, (1.0, 0.85, 0.82), np.clip(1.0 - band / 0.2, 0, 1) * 0.35)
save("meat_raw.png", col + rng.normal(0, 0.02, (H, W, 1)))

# ---------- 沙威核 (金屬 + 發光紋路) ----------
metal = lerp((0.22, 0.2, 0.26), (0.38, 0.36, 0.42), pnoise(3, 2, 4, 9))
bands = (np.abs(((X / W * 24) % 1) - 0.5) < 0.04).astype(float)       # 直的發光線
rings = (np.abs(((Y / H * 6) % 1) - 0.5) > 0.47).astype(float)        # 橫的接縫
rune = np.clip((pnoise(3, 6, 1, 10) - 0.75) * 6, 0, 1) * (np.abs(((X / W * 12) % 1) - 0.5) < 0.18)
glow = np.clip(bands + rune, 0, 1)
col = lerp(metal, (0.12, 0.1, 0.12), rings)
col = lerp(col, (1.0, 0.55, 0.12), glow)
save("core.png", col)
