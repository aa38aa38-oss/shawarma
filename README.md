# 沙威瑪斬 SHAWARMA SLASH

奇異果英雄傳 外傳：柯基英雄拿光劍，砍殺會自己長肉的旋轉沙威瑪！

## 怎麼玩

旋轉的「沙威核」會不停長出肉。**砍肉的速度要比長肉更快**，把六面的肉全部砍光，
再趁肉長回來之前破壞沙威核。共 3 關。

| 動作 | 鍵盤 | 手機 |
|---|---|---|
| 移動（走到邊緣會繞著沙威瑪轉） | ← → | ◀ ▶ |
| 跳（可二段跳） | Z / 空白鍵 | 跳 |
| 斬（連打更快，第 3 下是大斬） | X | 斬 |
| 上斬（砍上面的肉） | ↑ + X | ▲ + 斬 |
| 衝刺 | C / Shift | 衝 |

- 右上角的「六面圖」：下方那一面就是正對你的面，綠色表示這面已經砍乾淨。
- 砍光的地方，旁邊有厚肉的話會冒出粉紅色肉芽，過幾秒又長出肉。
- 小心頭上滴下來的熱油，還有沙威核露出時從地面打出來的震波。

## 偽 3D 怎麼做的（方案 C）

完全沒有 3D 模型。沙威瑪被切成 24 直條 × 6 橫列的「肉格子」，每格記錄肉量 0~100。
畫面時，每一直條依照它目前的角度 `a` 算出：

- 螢幕 x = 中心 + 半徑 × sin(a)（越靠邊越窄）
- 明暗 = cos(a)（正面亮、側邊暗）
- 肉越厚，半徑越大，所以砍過的地方會凹下去、露出沙威核

主角走到畫面邊緣時，改成轉動視角（`phi`），所以看起來像是繞著沙威瑪走。
核心程式在 `game/scripts/main.gd` 的 `_pp()` 與 `_draw_shawarma()`。

## 專案結構

```
game/            Godot 4.3 專案（用 Godot 打開 game/project.godot）
  scripts/main.gd    全部遊戲邏輯與繪圖
  assets/            主角圖、音效、BGM、字型、手機按鈕
docs/            匯出好的網頁版（GitHub Pages 直接放這個資料夾）
tools/           素材產生腳本
```

## 修改後重新匯出網頁版

1. 安裝 [Godot 4.3](https://godotengine.org/download/archive/4.3-stable/) 與 Web 匯出模板。
2. 用 Godot 打開 `game/project.godot`，選「專案 → 匯出 → Web」，匯出到 `docs/index.html`。
   或用指令：`godot --headless --path game --export-release "Web" ../docs/index.html`
3. 如果改了畫面上的中文字，要重新跑 `python3 tools/make_font.py`（字型只保留用得到的字）。

測試用：網址加上 `?autoplay` 會讓電腦自己玩（展示模式）。

## 素材來源

- 主角圖：取自 [kiwi-Legend](https://github.com/aa38aa38-oss/kiwi-Legend)（奇異果英雄傳）
- 音效與 BGM：`tools/make_assets.py` 程式合成
- 字型：文泉驛正黑（WenQuanYi Zen Hei，GPL + 字型嵌入例外），只保留遊戲用到的字
