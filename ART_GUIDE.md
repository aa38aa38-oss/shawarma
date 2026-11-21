# 美術製作指南（用 Gemini 生圖）

生好的圖放進 `art_src/`，**檔名照下面的表**，然後跑：

```
python3 tools/import_art.py      # 自動去背、裁切、找腳底對齊點、切 sprite sheet
```

再用 Godot 匯出網頁版（或直接把圖傳到 GitHub 的 `art_src/`，請 Claude 幫你匯入＋匯出）。

缺的圖沒關係，遊戲會自動用替代圖（例如沒有 `run` 就用 `idle` 加彈跳）。

---

## 一、沙威瑪貼圖 `art_src/shawarma/`

遊戲把沙威瑪當成一根圓柱，**貼圖是「把圓柱表面攤平」的長方形**，會繞一圈貼上去。
所以要：正面平視、沒有透視、沒有背景、填滿整張圖、**左右邊緣能接起來**（不完美也沒關係，匯入工具會自動修接縫）。
比例建議 **寬:高 = 5:2**（Gemini 選 16:9 也可以，工具會縮放成 1024×400）。

| 檔名 | 內容 |
|---|---|
| `meat_surface.png` | 烤好的肉表面（最重要） |
| `meat_raw.png` | 剛長出來的生肉（長肉特效用） |
| `core.png` | 沙威核的表面（肉砍光後露出來的部分） |

### meat_surface.png 提示詞

> Seamless tileable texture, flat orthographic close-up of the outer surface of a Middle Eastern shawarma / doner kebab meat cone, unwrapped into a flat wide rectangle. Many thin slices of roasted meat stacked horizontally, juicy and thick, golden-brown crispy caramelized edges, darker charred tips, glistening fat and dripping juices, glossy highlights. Even flat lighting, no perspective, no background, the meat fills the entire frame edge to edge. Left and right edges tile seamlessly. 16-bit SNES pixel-art game style like Mega Man X4, rich detail. Wide aspect ratio 5:2.

### meat_raw.png 提示詞

> Same style and layout as the previous image, but the meat is raw and freshly grown: pink and red raw meat layers with white fat marbling, moist and wet, slightly translucent. Seamless tileable, flat orthographic, fills the entire frame, no background, 16-bit pixel-art game style, wide 5:2.

（先生 meat_surface，再把它丟回 Gemini 說「同樣構圖改成生肉」，兩張的紋路會比較對得上。）

### core.png 提示詞

> Seamless tileable texture, flat orthographic unwrapped surface of a magical mechanical cylinder core: dark gunmetal steel plates with glowing orange-yellow energy lines running vertically and glowing ancient runes, hot and menacing. Fills the entire frame, no background, no perspective. 16-bit pixel-art game style like Mega Man X4. Wide 5:2.

---

## 二、柯基傑洛 `art_src/hero/`

**最重要的幾條規則：**

1. 把現在的主角圖（例如 kiwi-Legend 的 `player.png`）**上傳給 Gemini 當參考**，說「use this exact character design」，造型才會一致。
2. 背景一律 **純洋紅色 #FF00FF**（光劍是綠色，所以不能用綠幕）。
3. 角色**面向右邊**（往左時遊戲會自動翻轉）。
4. **偏正面 3/4 視角**：身體朝右前方，臉看得到、看得到胸口，像格鬥遊戲的站姿。
5. 全身入鏡、不要地面陰影、不要文字。
6. 同一個動作的多格，**橫排在同一張圖裡、中間留空隙**，工具會自動切開。也可以一格一張：`slash1_0.png`、`slash1_1.png`。

| 檔名 | 動作 | 建議格數 |
|---|---|---|
| `idle.png` | 待機站姿（呼吸起伏） | 2～4 |
| `run.png` | 跑步 | 4～6 |
| `jump.png` | 往上跳 | 1～2 |
| `fall.png` | 往下落 | 1 |
| `slash1.png` | 第 1 斬：由上往下斜劈 | 3 |
| `slash2.png` | 第 2 斬：反手橫掃 | 3 |
| `slash3.png` | 第 3 斬：大迴旋斬（最帥的一刀） | 3～4 |
| `upslash.png` | 往上斬（升龍斬） | 2～3 |
| `dash.png` | 衝刺 | 1～2 |
| `hurt.png` | 被打到 | 1 |
| `die.png` | 倒下 | 1～2 |
| `win.png` | 勝利姿勢 | 1～2 |

斬擊的 3 格建議是：**舉刀 → 揮到一半(刀光最大) → 收刀**。

### 共用提示詞（每個動作都先貼這段）

> Use this exact character design as reference: a corgi dog hero in red Zero-style armor from Mega Man X, white long hair, green beam saber. 16-bit SNES pixel-art sprite style like Mega Man X4. Three-quarter front view: the body faces to the right but turned toward the viewer so the face and chest are visible. Full body, no ground shadow, no text. Solid flat magenta background #FF00FF.

### 各動作加在後面

- **idle**：`Sprite sheet of 3 frames in one horizontal row with empty space between them: idle battle stance, holding the green beam saber low, subtle breathing animation.`
- **run**：`Sprite sheet of 6 frames in one horizontal row with space between: running cycle to the right, saber held back.`
- **slash1**：`Sprite sheet of 3 frames in one horizontal row with space between: a powerful diagonal downward slash with the green beam saber toward the right and slightly toward the viewer: 1) raising the saber, 2) mid-swing with a big bright green crescent slash trail, 3) follow-through.`
- **slash2**：`...3 frames: a fast horizontal backhand slash to the right with a wide green slash trail...`
- **slash3**：`...4 frames: a spinning finishing slash, the character spins and unleashes a huge green crescent energy arc, most dramatic pose...`
- **upslash**：`...3 frames: a rising uppercut slash, jumping upward with the saber swinging straight up, vertical green slash trail above the head...`
- **jump**：`Single frame: jumping upward, knees tucked, saber raised.`
- **fall**：`Single frame: falling down, legs extended, ready to land.`
- **dash**：`Single frame: fast forward dash to the right, body leaning forward, speed lines.`
- **hurt**：`Single frame: getting hit, flinching backward, eyes shut.`
- **die**：`Single frame: knocked down, sitting on the ground exhausted, sparks from the armor.`
- **win**：`Single frame: victory pose, saber raised to the sky, happy face.`

### 大小不對怎麼辦

每個動作在畫面上的高度寫在 `tools/import_art.py` 的 `HERO_HEIGHT`。
如果某個動作看起來太大/太小，建立 `art_src/hero/config.json`：

```json
{ "slash3": {"height": 140}, "dash": {"height": 130} }
```

---

## 三、目前的替代圖

`art_src/` 裡現在放的是：

- 主角：kiwi-Legend 的側面圖（idle / jump / slash1 / dash / die）
- 沙威瑪：`tools/make_placeholder_textures.py` 用程式畫的

直接用 Gemini 的圖覆蓋同名檔案就好。
