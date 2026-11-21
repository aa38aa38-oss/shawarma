# 沙威瑪斬 SHAWARMA SLASH

奇異果英雄傳 外傳：柯基英雄拿光劍，砍殺會自己長肉的旋轉沙威瑪！

## 怎麼玩

夜市的沙威瑪活過來了！每一關有一整排沙威瑪，一根接一根滑進烤爐，最後一根是**巨無霸 BOSS**。

1. 沙威瑪會一直長肉，**砍肉的速度要比長肉快**。
2. 肉砍光，「沙威核」就會露出來，趁肉長回來之前把它打爆。
3. 打爆後馬上換下一根。斬殺得越快，速度獎勵越高；每打爆一根會回一點血。

共 3 關：夜市第一攤（6 根）、辣味大街（8 根）、沙威瑪工廠（9 根）。
一般沙威瑪大約 6～10 秒砍完，BOSS 大約 20 秒。

| 動作 | 鍵盤 | 手機 |
|---|---|---|
| 移動（走到邊緣會繞著沙威瑪轉） | ← → | ◀ ▶ |
| 跳（可二段跳） | Z / 空白鍵 | 跳 |
| 斬（連打更快，第 3 下是大斬） | X | 斬 |
| 上斬（砍上面的肉） | ↑ + X | ▲ + 斬 |
| 衝刺 | C / Shift | 衝 |

- 上方中間的小方塊是這一關的沙威瑪排隊進度；右上角的「六面圖」顯示目前這根的六個面，下方是正對你的面，綠色表示已砍乾淨。
- 雞肉：小根、長得慢。牛肉：比較高、肉比較多。辣味：轉得快、熱油滴得多。
- 砍光的地方，旁邊有厚肉的話會冒出粉紅色肉芽，過幾秒又長出肉。
- 小心頭上滴下來的熱油，還有沙威核露出時從地面打出來的震波。

## 偽 3D 怎麼做的（方案 C）

完全沒有 3D 模型。沙威瑪被切成 24 直條 × 4～6 橫列的「肉格子」，每格記錄肉量 0~100。
肉的樣子是一張「把圓柱表面攤平」的貼圖，每一直條貼對應的那一段，所以轉起來就是真的在轉。
畫面時，每一直條依照它目前的角度 `a` 算出：

- 螢幕 x = 中心 + 半徑 × sin(a)（越靠邊越窄）
- 明暗 = cos(a)（正面亮、側邊暗）
- 肉越厚，半徑越大，所以砍過的地方會凹下去、露出沙威核

主角走到畫面邊緣時，改成轉動視角（`phi`），所以看起來像是繞著沙威瑪走。
核心程式在 `game/scripts/shawarma.gd`（一根沙威瑪的資料與 `pp()` 投影）和 `game/scripts/main.gd` 的 `_draw_shawarma()`。

肉的特效：旋轉時從兩側甩出肉汁、肉汁沿表面往下流、冒蒸氣、油花閃光；
長肉時格子會「鼓起來」、新長的肉是粉紅生肉並冒泡泡、空格會蠕動冒出肉芽；
砍到時噴肉汁、飛出真正的肉塊（從肉貼圖切下來的）。

## 換成 Gemini 生的圖

請看 **[ART_GUIDE.md](ART_GUIDE.md)**：裡面有每張圖的檔名、Gemini 提示詞、去背規則。
圖放進 `art_src/` 之後跑 `python3 tools/import_art.py`，再重新匯出網頁版。

## 專案結構

```
art_src/         原始美術 (Gemini 生的圖放這裡)
  hero/            主角各動作
  shawarma/        肉貼圖、生肉貼圖、沙威核貼圖
game/            Godot 4.3 專案（用 Godot 打開 game/project.godot）
  scripts/main.gd      遊戲流程、主角、繪圖、特效
  scripts/shawarma.gd  一根沙威瑪的資料（肉格子、生長、被砍）
  assets/              匯入後的素材 (由 tools/import_art.py 產生)
docs/            匯出好的網頁版（GitHub Pages 直接放這個資料夾）
tools/           素材工具：import_art.py、make_font.py、make_assets.py (音效)
```

## 修改後重新匯出網頁版

1. 安裝 [Godot 4.3](https://godotengine.org/download/archive/4.3-stable/) 與 Web 匯出模板。
2. 用 Godot 打開 `game/project.godot`，選「專案 → 匯出 → Web」，匯出到 `docs/index.html`。
   或用指令：`godot --headless --path game --export-release "Web" ../docs/index.html`
3. 如果改了畫面上的中文字，要重新跑 `python3 tools/make_font.py`（字型只保留用得到的字）。

測試用：網址加上 `?autoplay` 會讓電腦自己玩（展示模式）。

## 素材來源

- 主角圖：暫時取自 [kiwi-Legend](https://github.com/aa38aa38-oss/kiwi-Legend)（奇異果英雄傳），之後換成 Gemini 版
- 沙威瑪貼圖：暫時由 `tools/make_placeholder_textures.py` 程式產生
- 音效與 BGM：`tools/make_assets.py` 程式合成
- 字型：文泉驛正黑（WenQuanYi Zen Hei，GPL + 字型嵌入例外），只保留遊戲用到的字
