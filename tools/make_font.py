#!/usr/bin/env python3
"""把文泉驛正黑字型裁成只含遊戲用到的字 (網頁版才不會太大)。"""
import os, string
from fontTools import subset
from fontTools.ttLib import TTCollection
ROOT = os.path.join(os.path.dirname(__file__), "..")
src = "".join(open(os.path.join(ROOT, "game/scripts", f), encoding="utf-8").read() for f in os.listdir(os.path.join(ROOT, "game/scripts")) if f.endswith(".gd"))
chars = set(string.printable) | {c for c in src if ord(c) > 127} | set("←→↑↓！？…「」：，。、%")
ttc = TTCollection("/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc")
font = ttc.fonts[0]
opts = subset.Options()
opts.layout_features = ["*"]
sub = subset.Subsetter(opts)
sub.populate(text="".join(sorted(chars)))
sub.subset(font)
out = os.path.join(ROOT, "game/assets/font.ttf")
font.save(out)
print(len(chars), "chars ->", os.path.getsize(out), "bytes")
