#!/usr/bin/env python3
"""用 Gemini 生遊戲美術（在開發時生一次，存進專案；金鑰不會出現在網頁版裡）。

  python3 tools/gemini_art.py models                 # 列出可用的生圖模型
  python3 tools/gemini_art.py story [1 2 3 4]        # 開場故事圖 → art_src/story/
  python3 tools/gemini_art.py texture --ref a.jpg    # 沙威瑪肉貼圖 (可附真實照片當參考)

金鑰：環境變數 GEMINI_API_KEY，或由執行環境的網路代理自動帶上 x-goog-api-key。
"""
import base64, json, os, sys, urllib.request, urllib.error, argparse, io

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
API = "https://generativelanguage.googleapis.com/v1beta"
KEY = os.environ.get("GEMINI_API_KEY", "")

STYLE = ("16-bit SNES pixel-art cutscene illustration in the style of Mega Man X4 intro scenes, "
         "rich colors, dramatic lighting, crisp pixels, cinematic 16:9 composition, no text, no speech bubbles, no watermark.")
HERO = ("The hero is the exact character in the reference image: a corgi dog in red Zero-style armor "
        "with a white-blue helmet, long white hair and a green beam saber.")

STORY = {
    1: "A Taiwanese night market late at night, neon signs and food stalls. At a shawarma stall, a huge vertical "
       "shawarma (stacked roasted chicken slices on a rotating spit, a lemon on top, a glowing grill heater beside it) "
       "starts to emit an eerie orange glow from inside. Mysterious, ominous mood. No people in focus.",
    2: "The giant shawarma has come alive: a glowing mechanical core inside the meat cone opens one angry red eye, "
       "and roasted meat keeps growing and bulging out of it, juices splashing, flooding the night market street "
       "with meat. Panicking silhouettes of people run away. Epic kaiju-like scene.",
    3: "Hero introduction shot: " + "{HERO}" + " He stands on a night market rooftop, three-quarter front view, "
       "drawing the green beam saber with a bright flash, wind blowing his white hair, determined face, "
       "the glowing shawarma monster in the distance behind him.",
    4: "Action shot: " + "{HERO}" + " He leaps toward the giant rotating shawarma and slashes with a huge green "
       "crescent energy arc, meat slices and juice flying everywhere, sparks, speed lines, explosive dynamic composition.",
}

TEXTURE = ("Create a seamless tileable texture: a flat, orthographic, unwrapped view of the outer surface of a "
           "rotating chicken shawarma / doner kebab meat cone, like the reference photos. Many thin slices of meat "
           "stacked horizontally with uneven curly edges, golden-brown crispy caramelized edges, paler juicy cooked "
           "chicken between them, a few charred tips, glistening fat and juices. Even flat lighting, no perspective, "
           "no background, no spit, the meat fills the whole frame edge to edge, the left and right edges tile "
           "seamlessly. Slightly stylized 16-bit pixel-art game texture. Wide 21:9 aspect ratio.")


def req(method, path, body=None):
    url = API + path
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method, headers={"Content-Type": "application/json"})
    if KEY:
        r.add_header("x-goog-api-key", KEY)
    try:
        with urllib.request.urlopen(r, timeout=300) as f:
            return json.loads(f.read())
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code}: {e.read().decode()[:800]}")


def image_models():
    out = []
    tok = ""
    while True:
        res = req("GET", "/models?pageSize=200" + (f"&pageToken={tok}" if tok else ""))
        for m in res.get("models", []):
            name = m["name"].split("/")[-1]
            if "image" in name and "generateContent" in m.get("supportedGenerationMethods", []):
                out.append(name)
        tok = res.get("nextPageToken", "")
        if not tok:
            return out


def pick_model(pref=None):
    ms = image_models()
    if pref:
        return pref
    if not ms:
        sys.exit("找不到可以生圖的 Gemini 模型")
    # 優先 pro，再來版本號大的
    ms.sort(key=lambda n: (("pro" in n), n), reverse=True)
    return ms[0]


def part_image(path):
    from PIL import Image
    im = Image.open(path).convert("RGB")
    im.thumbnail((1024, 1024))
    b = io.BytesIO()
    im.save(b, "PNG")
    return {"inline_data": {"mime_type": "image/png", "data": base64.b64encode(b.getvalue()).decode()}}


def generate(model, prompt, refs, aspect, out_path):
    parts = [part_image(p) for p in refs] + [{"text": prompt}]
    body = {"contents": [{"parts": parts}],
            "generationConfig": {"responseModalities": ["TEXT", "IMAGE"], "imageConfig": {"aspectRatio": aspect}}}
    res = req("POST", f"/models/{model}:generateContent", body)
    for c in res.get("candidates", []):
        for p in c.get("content", {}).get("parts", []):
            d = p.get("inline_data") or p.get("inlineData")
            if d:
                os.makedirs(os.path.dirname(out_path), exist_ok=True)
                open(out_path, "wb").write(base64.b64decode(d["data"]))
                print("寫入", out_path)
                return True
    print("沒有拿到圖：", json.dumps(res)[:600])
    return False


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["models", "story", "texture"])
    ap.add_argument("which", nargs="*", type=int)
    ap.add_argument("--ref", action="append", default=[])
    ap.add_argument("--model")
    a = ap.parse_args()
    if a.cmd == "models":
        print("\n".join(image_models()))
        sys.exit()
    model = pick_model(a.model)
    print("使用模型", model)
    if a.cmd == "story":
        hero_ref = os.path.join(ROOT, "art_src", "hero", "idle.png")
        for i in (a.which or sorted(STORY)):
            prompt = STORY[i].replace("{HERO}", HERO) + " " + STYLE
            refs = ([hero_ref] if "{HERO}" in STORY[i] else []) + a.ref
            generate(model, prompt, refs, "16:9", os.path.join(ROOT, "art_src", "story", f"story_{i}.png"))
    else:
        generate(model, TEXTURE, a.ref, "21:9", os.path.join(ROOT, "art_src", "shawarma", "meat_surface.png"))
