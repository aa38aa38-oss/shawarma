#!/usr/bin/env python3
"""把 art_src/ 裡的原始圖 (例如 Gemini 生的) 轉成遊戲用的素材。

  python3 tools/import_art.py

主角 art_src/hero/<動作>.png
  - 背景是洋紅色 #FF00FF (或已經是透明 PNG) 都可以，洋紅色會自動去背。
  - 一張圖裡可以橫排好幾格動作 (sprite sheet)，中間留背景空隙就會自動切開。
  - 也可以分開放：slash1_0.png、slash1_1.png ...
  - 自動找腳底位置當作對齊點，所以每格不用精準對齊。

沙威瑪 art_src/shawarma/
  meat_surface.png / meat_raw.png / core.png ：攤平的表面貼圖，左右要能無縫相接。

輸出到 game/assets/hero/、game/assets/shawarma/，以及 game/assets/art.json
"""
import os, re, json, glob
import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SRC = os.path.join(ROOT, "art_src")
OUT = os.path.join(ROOT, "game", "assets")

# 每個動作在畫面上的高度 (px)：以整張圖去背後的高度為準
HERO_HEIGHT = {
    "idle": 112, "run": 112, "jump": 128, "fall": 128,
    "slash1": 108, "slash2": 108, "slash3": 122, "upslash": 150,
    "dash": 150, "hurt": 112, "die": 110, "win": 120,
}
HERO_FPS = {"idle": 6, "run": 12, "jump": 10, "fall": 10, "dash": 16, "hurt": 10, "die": 6, "win": 6}
# 可以用 art_src/hero/config.json 覆蓋，例如 {"slash3": {"height": 140}}


def key_out(im):
    """洋紅去背 + 去掉邊緣洋紅色溢色"""
    im = im.convert("RGBA")
    a = np.asarray(im).astype(np.float32)
    rgb, alpha = a[..., :3], a[..., 3]
    if alpha.min() < 250:  # 已經有透明背景
        return im
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    # 洋紅程度：R、B 高，G 低
    mag = np.minimum(r, b) - g
    alpha = np.clip(255 - (mag - 60) * 3.0, 0, 255)
    # 去溢色：把偏洋紅的邊緣顏色拉回來
    spill = np.clip(np.minimum(r, b) - g - 20, 0, None)
    rgb[..., 0] -= spill * 0.6
    rgb[..., 2] -= spill * 0.6
    out = np.dstack([np.clip(rgb, 0, 255), alpha]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def split_frames(im):
    """依透明的直欄空隙切成多格"""
    a = np.asarray(im)[..., 3] > 30
    cols = a.any(axis=0)
    frames, start, gap = [], None, 0
    min_gap = max(6, im.width // 100)
    for x, filled in enumerate(cols):
        if filled:
            if start is None:
                start = x
            gap = 0
        elif start is not None:
            gap += 1
            if gap >= min_gap:
                frames.append((start, x - gap + 1))
                start, gap = None, 0
    if start is not None:
        frames.append((start, len(cols)))
    # 太窄的雜點不要
    frames = [f for f in frames if f[1] - f[0] > im.width * 0.04]
    return [im.crop((x0, 0, x1, im.height)) for x0, x1 in frames] or [im]


def trim(im):
    a = im.split()[3].point(lambda v: 255 if v > 30 else 0)
    bb = a.getbbox()
    return im.crop(bb) if bb else im


def feet_anchor(im):
    """腳底中心：最下面 8% 有像素的地方取平均 x"""
    a = np.asarray(im)[..., 3] > 60
    rows = np.where(a.any(axis=1))[0]
    bottom = rows.max()
    band = a[max(0, bottom - int(im.height * 0.08)): bottom + 1]
    xs = np.where(band.any(axis=0))[0]
    return float(xs.mean() / im.width), float((bottom + 1) / im.height)


def import_hero(meta):
    cfg_path = os.path.join(SRC, "hero", "config.json")
    cfg = json.load(open(cfg_path, encoding="utf-8")) if os.path.exists(cfg_path) else {}
    out_dir = os.path.join(OUT, "hero")
    os.makedirs(out_dir, exist_ok=True)
    for f in glob.glob(os.path.join(out_dir, "*.png")):
        os.remove(f)
    groups = {}
    for path in sorted(glob.glob(os.path.join(SRC, "hero", "*.png")) + sorted(glob.glob(os.path.join(SRC, "hero", "*.jpg")))):
        name = os.path.splitext(os.path.basename(path))[0]
        m = re.match(r"^([a-z0-9]+?)(?:_(\d+))?$", name)
        if not m:
            print("略過 (檔名看不懂):", name)
            continue
        groups.setdefault(m.group(1), []).append(path)
    hero = {}
    for action, paths in groups.items():
        frames = []
        for p in paths:
            frames += split_frames(key_out(Image.open(p)))
        frames = [trim(f) for f in frames]
        c = cfg.get(action, {})
        target = c.get("height", HERO_HEIGHT.get(action, 112)) * 2  # 存 2 倍大，遊戲裡縮 0.5
        ref_h = max(f.height for f in frames)  # 同一動作用同一個縮放比例
        scale = target / ref_h
        info = []
        for i, f in enumerate(frames):
            f = f.resize((max(1, round(f.width * scale)), max(1, round(f.height * scale))), Image.LANCZOS)
            ax, ay = feet_anchor(f)
            ax = c.get("ax", ax)
            fn = f"hero/{action}_{i}.png"
            f.save(os.path.join(OUT, fn))
            info.append({"file": fn, "ax": round(ax, 3), "ay": round(ay, 3)})
        hero[action] = {"frames": info, "fps": c.get("fps", HERO_FPS.get(action, 10))}
        print(f"hero {action}: {len(info)} 格")
    meta["hero"] = hero


def import_shawarma(meta):
    out_dir = os.path.join(OUT, "shawarma")
    os.makedirs(out_dir, exist_ok=True)
    for name in ["meat_surface", "meat_raw", "core"]:
        cands = glob.glob(os.path.join(SRC, "shawarma", name + ".*"))
        if not cands:
            print("缺少", name)
            continue
        im = Image.open(cands[0]).convert("RGB")
        # 統一成 1024x400；左右再做一次淡入淡出接縫，避免 Gemini 圖接不起來
        im = im.resize((1024, 400), Image.LANCZOS)
        a = np.asarray(im).astype(np.float32)
        # 無縫化：邊緣 10% 和「左右對調」的圖交叉淡化 (對調後原本的接縫跑到中間，邊緣就連續了)
        rolled = np.roll(a, a.shape[1] // 2, axis=1)
        x = np.arange(a.shape[1]) / (a.shape[1] - 1)
        w = np.clip(np.minimum(x, 1 - x) / 0.1, 0, 1)[None, :, None]
        a = a * w + rolled * (1 - w)
        Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(os.path.join(out_dir, name + ".png"))
        print("shawarma", name)


def import_story():
    out_dir = os.path.join(OUT, "story")
    os.makedirs(out_dir, exist_ok=True)
    for path in sorted(glob.glob(os.path.join(SRC, "story", "story_*.*"))):
        name = os.path.splitext(os.path.basename(path))[0]
        im = Image.open(path).convert("RGB")
        im.thumbnail((960, 540), Image.LANCZOS)
        im.save(os.path.join(out_dir, name + ".png"))
        print("story", name, im.size)


if __name__ == "__main__":
    meta = {}
    import_hero(meta)
    import_shawarma(meta)
    import_story()
    json.dump(meta, open(os.path.join(OUT, "art.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("寫入 art.json")
