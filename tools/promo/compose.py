"""ZORX promo clips (Boss 2026-11-15): turns the frames saved by tools/promo/promo_capture.gd into vertical
1080x1920 60 fps H.264 clips with burned-in Thai + English captions (hub fonts Taviraj / Sarabun).

    python tools/promo/compose.py [clip1 clip2 clip3 clip4]

Input:  %TEMP%/zorx_promo_frames/{card,battle,hub}/<shot>/<frame>.jpg + manifest.json (ZORX_PROMO_FRAMES overrides)
Output: art_source/promo/2026-11-15/clipN_*.mp4 (silent), clipN_*_music.mp4 (with the game's own music),
        clipN_*_still.png, clipN_*_sheet.png (6 frames)
Post effects added here (not in the game): captions, the finger marker, the card light glint, the seal-break flash,
the end card layout, and the vertical recomposition of the landscape hub. Every picture under them is the game.
"""
import json
import math
import os
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

ROOT = Path(__file__).resolve().parents[2]
FRAMES = Path(os.environ.get("ZORX_PROMO_FRAMES", Path(os.environ["TEMP"]) / "zorx_promo_frames"))
OUT = ROOT / "art_source" / "promo" / "2026-11-15"
FFMPEG = os.environ.get("FFMPEG", r"C:/Users/wanwi/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-8.0.1-full_build/bin/ffmpeg.exe")
W, H, FPS = 1080, 1920, 60
# TikTok / Reels safe area: no key text in the top 220, bottom 380 or right 140 px. Captions stay centred on x 540
# and at most 800 px wide (140..940).
SAFE_TOP, SAFE_BOTTOM, SAFE_RIGHT = 220, 380, 140
TEXT_W = 800
CREAM, GILT, INK, EDGE = (243, 230, 200), (233, 201, 135), (58, 36, 20), (28, 18, 11)
TAVIRAJ = str(ROOT / "art/fonts/Taviraj-SemiBold.woff2")
SARABUN = str(ROOT / "art/fonts/Sarabun-SemiBold.woff2")
MUSIC = {"stage": ROOT / "audio/music/stage_ink_trail.ogg", "hub": ROOT / "audio/music/hub_ember_waltz.ogg"}


def font(path, size):
    return ImageFont.truetype(path, size, layout_engine=ImageFont.Layout.RAQM)


def manifest(run):
    return json.loads((FRAMES / run / "manifest.json").read_text(encoding="utf-8"))


def frame(run, shot, i):
    shot_dir = FRAMES / run / shot
    count = manifest_cache[run]["shots"][shot]["frames"]
    i = max(0, min(int(i), count - 1))
    return Image.open(shot_dir / ("%05d.jpg" % i)).convert("RGB")


manifest_cache = {}


def ease(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


# ------------------------------------------------------------------ captions
def caption_image(th, en, th_size=78, en_size=40):
    """Thai line (Taviraj) with a small English line under it, cream / gilt on a dark brush stroke."""
    tf, ef = font(TAVIRAJ, th_size), font(SARABUN, en_size)
    while tf.getlength(th) > TEXT_W and th_size > 40:
        th_size -= 2
        tf = font(TAVIRAJ, th_size)
    while ef.getlength(en) > TEXT_W and en_size > 24:
        en_size -= 1
        ef = font(SARABUN, en_size)
    pad = 26
    th_box = tf.getbbox(th, stroke_width=6)
    en_box = ef.getbbox(en, stroke_width=4)
    th_h, en_h = th_box[3] - th_box[1], en_box[3] - en_box[1]
    gap = 14
    if not en:
        en_box, en_h, gap = (0, 0, 0, 0), 0, 0
    w = int(max(th_box[2] - th_box[0], en_box[2] - en_box[0])) + pad * 2
    h = int(th_h + en_h + gap) + pad * 2
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    # soft ink wash behind the words (readable over a busy fight)
    wash = Image.new("L", (w, h), 0)
    ImageDraw.Draw(wash).rounded_rectangle((8, 8, w - 8, h - 8), radius=28, fill=150)
    wash = wash.filter(ImageFilter.GaussianBlur(10))
    img.paste(Image.new("RGBA", (w, h), EDGE + (255,)), (0, 0), wash)
    d = ImageDraw.Draw(img)
    d.text((w / 2, pad - th_box[1]), th, font=tf, fill=CREAM, anchor="ma", stroke_width=6, stroke_fill=EDGE)
    if en:
        d.text((w / 2, pad + th_h + gap - en_box[1]), en, font=ef, fill=GILT, anchor="ma", stroke_width=4, stroke_fill=EDGE)
    return img


class Caption:
    def __init__(self, th, en, start, end, top, fade=0.25, **kw):
        self.img = caption_image(th, en, **kw)
        self.start, self.end, self.top, self.fade = start, end, top, fade
        ink = self.img.getchannel("A").point(lambda v: 255 if v > 200 else 0).getbbox()  # the words, not the soft wash
        assert top + ink[1] >= SAFE_TOP and top + ink[3] <= H - SAFE_BOTTOM, (th, top, ink)
        assert 540 + self.img.width / 2 <= W - SAFE_RIGHT + 30, (th, self.img.width)

    def draw(self, canvas, t):
        if t < self.start or t > self.end:
            return
        a = min(1.0, (t - self.start) / self.fade, (self.end - t) / self.fade)
        rise = (1.0 - ease(min(1.0, (t - self.start) / 0.35))) * 24
        img = self.img
        if a < 1.0:
            img = img.copy()
            img.putalpha(img.getchannel("A").point(lambda v: int(v * a)))
        canvas.alpha_composite(img, (int(540 - img.width / 2), int(self.top + rise)))


# ------------------------------------------------------------------ picture helpers
def window(img, cx, cy, w):
    """A 9:16 window of width w (source px) centred on (cx, cy), clamped inside, scaled to 1080x1920."""
    h = w * H / W
    sw, sh = img.size
    if h > sh:
        h = sh
        w = h * W / H
    x0 = min(max(cx - w / 2, 0), sw - w)
    y0 = min(max(cy - h / 2, 0), sh - h)
    return img.resize((W, H), Image.LANCZOS, box=(x0, y0, x0 + w, y0 + h)), (x0, y0, w / W)


def blurred_fill(img, cx=None):
    """The picture itself, cropped to fill 9:16, blurred and dimmed (a backdrop for recomposed panels)."""
    sw, sh = img.size
    cx = sw / 2 if cx is None else cx
    bg, _ = window(img, cx, sh / 2, sh * W / H)
    small = bg.resize((W // 6, H // 6), Image.BILINEAR).filter(ImageFilter.GaussianBlur(4))
    bg = small.resize((W, H), Image.BILINEAR)
    return Image.blend(bg, Image.new("RGB", (W, H), (14, 16, 24)), 0.45)


def panel(canvas, img, box, width, top, cx=540):
    """Pastes source rect `box` scaled to `width`, with a dark rounded rim and a shadow. Returns (x0, y0, scale)."""
    crop = img.crop(box)
    scale = width / crop.width
    crop = crop.resize((int(width), int(crop.height * scale)), Image.LANCZOS)
    x0, y0 = int(cx - crop.width / 2), int(top)
    shadow = Image.new("L", (crop.width + 80, crop.height + 80), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((40, 48, crop.width + 40, crop.height + 48), radius=22, fill=190)
    shadow = shadow.filter(ImageFilter.GaussianBlur(16))
    canvas.paste((0, 0, 0), (x0 - 40, y0 - 40), shadow)
    mask = Image.new("L", crop.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, crop.width - 1, crop.height - 1), radius=18, fill=255)
    canvas.paste(crop, (x0, y0), mask)
    ImageDraw.Draw(canvas).rounded_rectangle((x0, y0, x0 + crop.width - 1, y0 + crop.height - 1), radius=18, outline=EDGE + (255,), width=5)
    return x0 - box[0] * scale, y0 - box[1] * scale, scale


def finger(canvas, x, y, pressed=1.0):
    """A soft fingertip marker (where the scripted touch is)."""
    r = 46
    layer = Image.new("RGBA", (r * 4, r * 4), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse((r, r, r * 3, r * 3), fill=(255, 255, 255, int(70 * pressed)), outline=(255, 255, 255, int(220 * pressed)), width=6)
    layer = layer.filter(ImageFilter.GaussianBlur(1.2))
    canvas.alpha_composite(layer, (int(x - r * 2), int(y - r * 2)))


def tap_ring(canvas, x, y, age):
    """An expanding ring for a tap, age 0..1."""
    if not 0.0 <= age <= 1.0:
        return
    r = 30 + 70 * ease(age)
    a = int(230 * (1.0 - age))
    layer = Image.new("RGBA", (300, 300), (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse((150 - r, 150 - r, 150 + r, 150 + r), outline=(255, 244, 214, a), width=8)
    canvas.alpha_composite(layer, (int(x - 150), int(y - 150)))


def glint(canvas, rect, t):
    """The card light flash: a warm diagonal streak sweeping across the card (t 0..1), clipped to the card."""
    if not 0.0 <= t <= 1.0:
        return
    x, y, w, h = [int(v) for v in rect]
    inset = int(w * 0.03)
    band = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(band)
    centre = -0.5 * w + t * 2.0 * w
    width = w * 0.16
    for k, (bw, val) in enumerate([(width * 1.8, 70), (width, 150), (width * 0.35, 255)]):
        pts = [(centre - bw / 2, 0), (centre + bw / 2, 0), (centre + bw / 2 - h * 0.55, h), (centre - bw / 2 - h * 0.55, h)]
        d.polygon(pts, fill=val)
    band = band.filter(ImageFilter.GaussianBlur(w * 0.02))
    clip = Image.new("L", (w, h), 0)
    ImageDraw.Draw(clip).rounded_rectangle((inset, inset, w - inset, h - inset), radius=int(w * 0.05), fill=255)
    strength = math.sin(t * math.pi)
    band = ImageChops.multiply(band, clip).point(lambda v: int(v * 0.85 * strength))
    light = Image.new("RGBA", (w, h), (255, 236, 196, 0))
    light.putalpha(band)
    region = canvas.crop((x, y, x + w, y + h))
    # additive-ish: screen the light onto the card
    lit = ImageChops.screen(region.convert("RGB"), Image.composite(Image.new("RGB", (w, h), (255, 236, 196)), Image.new("RGB", (w, h), 0), band))
    canvas.paste(lit.convert("RGBA"), (x, y))


def flash(canvas, a, color=(255, 248, 230)):
    if a <= 0:
        return
    canvas.alpha_composite(Image.new("RGBA", (W, H), color + (int(255 * min(1.0, a)),)))


def seal_ring(canvas, t, cx=540, cy=960):
    """The seal breaking: a gold ring bursting out (t 0..1)."""
    if not 0.0 <= t <= 1.0:
        return
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    r = 80 + 1100 * ease(t)
    a = int(255 * (1.0 - t))
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=(233, 190, 100, a), width=int(26 * (1.0 - t)) + 2)
    r2 = r * 0.7
    d.ellipse((cx - r2, cy - r2, cx + r2, cy + r2), outline=(255, 240, 200, int(a * 0.7)), width=int(10 * (1.0 - t)) + 1)
    for k in range(12):
        ang = k * math.pi / 6 + 0.2
        r0, r1 = r * 0.35, r * 0.95
        d.line((cx + math.cos(ang) * r0, cy + math.sin(ang) * r0, cx + math.cos(ang) * r1, cy + math.sin(ang) * r1), fill=(255, 230, 170, int(a * 0.8)), width=6)
    canvas.alpha_composite(layer.filter(ImageFilter.GaussianBlur(2)))


# ------------------------------------------------------------------ end card
_end_assets = {}


def end_assets():
    if _end_assets:
        return _end_assets
    back = Image.open(ROOT / "art/ui/hub_carved/backdrop.png").convert("RGB")
    s = H / back.height
    back = back.resize((int(back.width * s), H), Image.LANCZOS)
    x0 = int(back.width * 0.30 - W / 2)  # the campfire side of the valley
    back = back.crop((x0, 0, x0 + W, H))
    vignette = Image.new("L", (W, H), 0)
    ImageDraw.Draw(vignette).ellipse((-300, 200, W + 300, H + 200), fill=255)
    vignette = vignette.filter(ImageFilter.GaussianBlur(160))
    dark = Image.new("RGB", (W, H), (10, 12, 20))
    back = Image.composite(Image.blend(back, dark, 0.35), dark, vignette)
    ribbon = Image.open(ROOT / "art/ui/hub_carved/title_ribbon.png").convert("RGBA")
    rw = 860
    ribbon = ribbon.resize((rw, int(ribbon.height * rw / ribbon.width)), Image.LANCZOS)
    d = ImageDraw.Draw(ribbon)
    zf = font(TAVIRAJ, 150)
    word = "Z O R X"
    # the name sits in the ribbon's flat upper band (the web page's .login-mark: inset 0 0 38% 0)
    d.text((rw / 2, ribbon.height * 0.31), word, font=zf, fill=INK, anchor="mm", stroke_width=2, stroke_fill=(255, 246, 224))
    hub = manifest_cache.get("hub")
    cards = None
    if hub:
        last = hub["shots"]["hub"]["frames"] - 1
        cards = frame("hub", "hub", last).crop((835, 215, 2810, 885))
        cw = 880
        cards = cards.resize((cw, int(cards.height * cw / cards.width)), Image.LANCZOS)
        mask = Image.new("L", cards.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, cards.width - 1, cards.height - 1), radius=16, fill=255)
        cards.putalpha(mask)
    _end_assets.update(back=back, ribbon=ribbon, cards=cards,
                       tag=caption_image("Squad of Four Races", "", th_size=60, en_size=10) if False else None)
    return _end_assets


def end_card(t, dur):
    """ZORX ribbon, "Squad of Four Races", the four cards, "เล่นบนเว็บ ฟรี" / "Play free in your browser"."""
    a = end_assets()
    canvas = a["back"].copy().convert("RGBA")
    pop = 0.86 + 0.14 * ease(t / 0.45)
    rib = a["ribbon"]
    r = rib.resize((int(rib.width * pop), int(rib.height * pop)), Image.LANCZOS)
    canvas.alpha_composite(r, (int(540 - r.width / 2), int(560 - r.height / 2)))
    d = ImageDraw.Draw(canvas)
    d.text((540, 742), "SQUAD OF FOUR RACES", font=font(TAVIRAJ, 50), fill=GILT, anchor="mm", stroke_width=4, stroke_fill=EDGE)
    if a["cards"] is not None:
        k = ease((t - 0.15) / 0.5)
        c = a["cards"].copy()
        c.putalpha(c.getchannel("A").point(lambda v: int(v * k)))
        canvas.alpha_composite(c, (100, int(820 + (1 - k) * 40)))
    k2 = ease((t - 0.35) / 0.4)
    play = caption_image("เล่นบนเว็บ ฟรี", "Play free in your browser", th_size=92, en_size=46)
    play.putalpha(play.getchannel("A").point(lambda v: int(v * k2)))
    canvas.alpha_composite(play, (int(540 - play.width / 2), 1210 + int((1 - k2) * 30)))
    return canvas


# ------------------------------------------------------------------ output
class Writer:
    def __init__(self, name, total_frames, still_at, music=None):
        OUT.mkdir(parents=True, exist_ok=True)
        self.name, self.total, self.still_at, self.music = name, total_frames, still_at, music
        self.path = OUT / (name + ".mp4")
        self.n = 0
        self.thumbs = []
        picks = [int(round(i * (total_frames - 1) / 5)) for i in range(6)]
        picks[0] = min(int(FPS * 0.6), total_frames - 1)
        self.picks = set(picks)
        self.proc = subprocess.Popen([FFMPEG, "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
                                      "-s", "%dx%d" % (W, H), "-r", str(FPS), "-i", "-",
                                      "-c:v", "libx264", "-preset", "slow", "-crf", "19", "-maxrate", "14M", "-bufsize", "28M",
                                      "-pix_fmt", "yuv420p", "-profile:v", "high", "-level", "4.2", "-g", "120",
                                      "-movflags", "+faststart", str(self.path)], stdin=subprocess.PIPE)

    def put(self, canvas):
        rgb = canvas.convert("RGB")
        if self.n == self.still_at:
            rgb.save(OUT / (self.name + "_still.png"))
        if self.n in self.picks:
            self.thumbs.append((self.n, rgb.resize((360, 640), Image.LANCZOS)))
        self.proc.stdin.write(rgb.tobytes())
        self.n += 1

    def close(self):
        self.proc.stdin.close()
        self.proc.wait()
        sheet = Image.new("RGB", (360 * 3 + 40, 640 * 2 + 30), (20, 20, 24))
        d = ImageDraw.Draw(sheet)
        for i, (n, im) in enumerate(self.thumbs[:6]):
            x, y = 10 + (i % 3) * 370, 10 + (i // 3) * 650
            sheet.paste(im, (x, y))
            # safe-area guides (top 220, bottom 380, right 140 at 1/3 scale)
            d.rectangle((x, y, x + 359, y + 639), outline=(80, 80, 90))
            d.line((x, y + 220 / 3, x + 359, y + 220 / 3), fill=(255, 80, 80))
            d.line((x, y + 640 - 380 / 3, x + 359, y + 640 - 380 / 3), fill=(255, 80, 80))
            d.line((x + 360 - 140 / 3, y, x + 360 - 140 / 3, y + 639), fill=(255, 80, 80))
            d.text((x + 6, y + 6), "%.2fs" % (n / FPS), font=font(SARABUN, 22), fill=(255, 255, 0), stroke_width=2, stroke_fill=(0, 0, 0))
        sheet.save(OUT / (self.name + "_sheet.png"))
        seconds = self.n / FPS
        if self.music:
            fade_at = max(0.0, seconds - 1.2)
            subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-i", str(self.path), "-i", str(self.music),
                            "-map", "0:v", "-map", "1:a", "-c:v", "copy", "-c:a", "aac", "-b:a", "160k",
                            "-af", "afade=t=in:d=0.4,afade=t=out:st=%.2f:d=1.2,volume=0.9" % fade_at,
                            "-t", "%.3f" % seconds, "-movflags", "+faststart", str(OUT / (self.name + "_music.mp4"))], check=True)
        print("%s: %d frames, %.2f s, %.1f MB" % (self.path.name, self.n, seconds, self.path.stat().st_size / 1e6))


def run_segments(name, segments, captions, still_at, music):
    total = sum(n for n, _ in segments)
    out = Writer(name, total, still_at, music)
    t0 = 0
    for count, draw in segments:
        for i in range(count):
            canvas = draw(i, count).convert("RGBA")
            t = (t0 + i) / FPS
            for c in captions:
                c.draw(canvas, t)
            out.put(canvas)
        t0 += count
    out.close()


# ------------------------------------------------------------------ clip 1: sealed cards
def touches_at(touches, n):
    """The finger state at frame n: (x, y, pressed) or None; and taps [(frame, x, y)]."""
    state = None
    for f, x, y, s in touches:
        if f > n:
            break
        state = None if s == -1 else (x, y)
    return state


def card_frame(shot, n, card_zoom=1.0, finger_on=True, glints=(), card_rect=None, zoom_centre=None):
    m = manifest_cache["card"]["shots"][shot]
    img = frame("card", shot, n)
    if card_zoom != 1.0:
        cx, cy = zoom_centre
        img, _ = window(img, cx, cy, W / card_zoom)
    canvas = img.convert("RGBA")
    for g0, g1 in glints:
        if g0 <= n <= g1:
            glint(canvas, card_rect, (n - g0) / (g1 - g0))
    if finger_on and card_zoom == 1.0:
        f = touches_at(m.get("touches", []), n)
        if f:
            finger(canvas, f[0], f[1])
    return canvas


def clip1():
    card = manifest_cache["card"]["shots"]["tilt"]
    rect = card["card"]
    g = [card["events"]["gesture_%d" % i] for i in range(3)]
    glints = [(s + 22, s + 48) for s in g]  # one light sweep per tilt, as the card swings across
    card_n = 312  # 5.2 s of the card
    burst = 24
    cx, cy = rect[0] + rect[2] / 2, rect[1] + rect[3] / 2
    fight = manifest_cache["battle"]["shots"]["fight"]
    b0 = fight["events"]["zoomed"] + 40
    battle_n = 270

    def card_seg(i, n):
        return card_frame("tilt", i, glints=glints, card_rect=rect)

    def burst_seg(i, n):
        k = ease(i / (n - 1))
        canvas = card_frame("tilt", card_n + i, card_zoom=1.0 + 0.45 * k, finger_on=False, zoom_centre=(cx, cy))
        flash(canvas, max(0.0, (k - 0.35) / 0.65) ** 1.4)
        seal_ring(canvas, k * 0.55)
        return canvas

    def battle_seg(i, n):
        canvas = frame("battle", "fight", b0 + i).convert("RGBA")
        flash(canvas, 1.0 - ease(i / 22.0))
        seal_ring(canvas, 0.55 + 0.45 * ease(i / 30.0))
        return canvas

    end_n = 150

    def end_seg(i, n):
        canvas = end_card(i / FPS, n / FPS)
        if i < 10:
            prev = frame("battle", "fight", b0 + battle_n - 1).convert("RGBA")
            canvas = Image.blend(prev, canvas, i / 10)
        return canvas

    t_card = card_n / FPS
    t_battle = (card_n + burst) / FPS
    caps = [
        Caption("ฮีโร่ถูกผนึกอยู่ในการ์ด", "Heroes sealed inside the cards", 0.35, t_card + 0.2, 236),
        Caption("ปลดผนึก แล้วส่งลงสนาม", "Break the seal. Send them in.", t_battle + 0.25, t_battle + battle_n / FPS - 0.05, 236),
    ]
    run_segments("clip1_sealed_cards", [(card_n, card_seg), (burst, burst_seg), (battle_n, battle_seg), (end_n, end_seg)],
                 caps, still_at=g[1] + 34, music=MUSIC["stage"])


# ------------------------------------------------------------------ clip 2: one card, four races
RACE_NAMES = {"human": ("มนุษย์", "Human"), "viking": ("ไวกิ้ง", "Viking"), "elf": ("เอลฟ์", "Elf"), "runeborn": ("รูนบอร์น", "Runeborn")}


def clip2():
    shot = manifest_cache["card"]["shots"]["races"]
    rect = shot["card"]
    ev = shot["events"]
    order = ["human", "viking", "elf", "runeborn"]
    starts = [ev["race_" + r] for r in order]
    zoom = 1.0
    cx, cy = rect[0] + rect[2] / 2, rect[1] + rect[3] / 2 - 10
    n_card = shot["frames"]
    # the card rect after the zoom window (for the glint)
    x0, y0 = cx - W / zoom / 2, cy - H / zoom / 2
    zrect = [(rect[0] - x0) * zoom, (rect[1] - y0) * zoom, rect[2] * zoom, rect[3] * zoom]
    glints = [(s + 2, s + 30) for s in starts[1:]]

    def card_seg(i, n):
        canvas = card_frame("races", i, card_zoom=zoom, finger_on=False, zoom_centre=(cx, cy))
        for g0, g1 in glints:
            if g0 <= i <= g1:
                glint(canvas, zrect, (i - g0) / (g1 - g0))
        for s in starts[1:]:
            if s <= i < s + 10:
                flash(canvas, 0.55 * (1.0 - (i - s) / 10.0), (255, 240, 205))
        return canvas

    end_n = 150

    def end_seg(i, n):
        canvas = end_card(i / FPS, n / FPS)
        if i < 10:
            canvas = Image.blend(card_frame("races", n_card - 1, card_zoom=zoom, finger_on=False, zoom_centre=(cx, cy)), canvas, i / 10)
        return canvas

    caps = [Caption("1 การ์ด 4 เผ่า", "One card, four races", 0.3, n_card / FPS - 0.05, 236)]
    # the race name under the card at each switch (bottom band, above the safe line)
    for k, r in enumerate(order):
        a = starts[k] / FPS + 0.05
        b = (starts[k + 1] / FPS if k + 1 < len(order) else n_card / FPS) - 0.05
        th, en = RACE_NAMES[r]
        caps.append(Caption(th + "  ·  " + en, "", a, b, 1430, fade=0.15, th_size=50, en_size=1))
    run_segments("clip2_races", [(n_card, card_seg), (end_n, end_seg)], caps, still_at=starts[3] + 60, music=MUSIC["hub"])


# ------------------------------------------------------------------ clip 3: squad + fight
def clip3():
    hub = manifest_cache["hub"]["shots"]
    rects = hub["hub"]["rects"]
    taps = [(f, x, y) for f, x, y, s in hub["hub"]["touches"] if s == 1]
    h0, hub_n = 30, 240
    cards_box = (835, 215, 2330, 885)  # the three squad cards (Sword & Shield, Great Sword, Longbow)
    tray_box = (865, 1240, 2185, 1590)  # the squad medallions + the Alliance line

    def hub_seg(i, n):
        f = h0 + i
        img = frame("hub", "hub", f)
        canvas = blurred_fill(img).convert("RGBA")
        cards_map = panel(canvas, img, cards_box, 1040, 250)
        tray_map = panel(canvas, img, tray_box, 1040, 820)
        for tf, x, y in taps:
            age = (f - tf) / 30.0
            m = cards_map if y < 1000 else tray_map
            tap_ring(canvas, m[0] + x * m[2], m[1] + y * m[2], age)
            if 0 <= f - tf < 4:
                finger(canvas, m[0] + x * m[2], m[1] + y * m[2])
        # the medallion that just filled (fly-in hint): the tray is where the picks land
        return canvas

    fshot = hub["fight"]
    ftap = fshot["events"]["tap"]
    fx, fy = fshot["touches"][0][1], fshot["touches"][0][2]
    hold = 14  # the pressed FIGHT frame is held so the tap reads (the game moved on in 2 frames)
    press_n = ftap + 2 + hold

    def press_seg(i, n):
        img = frame("hub", "fight", min(i, ftap + 1))
        k = ease(i / (ftap + 2))
        canvas, (x0, y0, s) = window(img, 2380, 1180, 1300 - 450 * k)
        canvas = canvas.convert("RGBA")
        sx, sy = (fx - x0) / s, (fy - y0) / s
        if i >= ftap:
            finger(canvas, sx, sy)
            tap_ring(canvas, sx, sy, (i - ftap) / 16.0)
        return canvas

    # the loading overlay held to 1 s: its frames once the fade-in is done (full colour) and before it fades out
    load_frames = [f for f in range(ftap + 9, ftap + 18) if f < fshot["frames"]]
    load_n = 60

    def load_seg(i, n):
        f = load_frames[min(len(load_frames) - 1, int(i * len(load_frames) / n))]
        img = frame("hub", "fight", f)
        canvas = blurred_fill(img).convert("RGBA")
        panel(canvas, img, (720, 470, 2160, 1070), 1040, 700)
        return canvas

    fight = manifest_cache["battle"]["shots"]["fight"]
    b0, battle_n = 120, 210
    boss = manifest_cache["battle"]["shots"]["boss"]
    s0, boss_n = boss["events"]["zoom_start"] + 30, 220

    def battle_seg(i, n):
        canvas = frame("battle", "fight", b0 + i).convert("RGBA")
        flash(canvas, 0.8 * (1.0 - ease(i / 14.0)))
        return canvas

    def boss_seg(i, n):
        canvas = frame("battle", "boss", s0 + i).convert("RGBA")
        if i < 8:
            canvas = Image.blend(frame("battle", "fight", b0 + battle_n - 1).convert("RGBA"), canvas, i / 8)
        return canvas

    end_n = 96

    def end_seg(i, n):
        canvas = end_card(i / FPS + 0.3, n / FPS)
        if i < 10:
            canvas = Image.blend(frame("battle", "boss", s0 + boss_n - 1).convert("RGBA"), canvas, i / 10)
        return canvas

    t_hub = hub_n / FPS
    t_bat = (hub_n + press_n + load_n) / FPS
    caps = [
        Caption("จัดทัพ 3 เผ่า", "Pick three races", 0.3, t_hub - 0.05, 1320),
        Caption("จัดทัพ 3 เผ่า แล้วดูมันสู้เอง", "Build a squad. Watch it fight.", t_bat + 0.15, t_bat + (battle_n + boss_n) / FPS - 0.1, 236),
    ]
    run_segments("clip3_squad_fight", [(hub_n, hub_seg), (press_n, press_seg), (load_n, load_seg), (battle_n, battle_seg),
                                       (boss_n, boss_seg), (end_n, end_seg)], caps,
                 still_at=hub_n + press_n + load_n + battle_n + 120, music=MUSIC["stage"])


# ------------------------------------------------------------------ clip 4: hub tour
def clip4():
    hub = manifest_cache["hub"]["shots"]

    def push(shot, first, box_from, box_to, top=430, width=1040):
        """The landscape screen as a big panel over its own blurred picture, pushing in from one crop to another."""
        def draw(i, n):
            k = ease(i / max(1, n - 1))
            img = frame("hub", shot, first + i)
            canvas = blurred_fill(img).convert("RGBA")
            box = tuple(a + (b - a) * k for a, b in zip(box_from, box_to))
            aspect = (box[3] - box[1]) / (box[2] - box[0])
            panel(canvas, img, box, width, 820 - aspect * width / 2)  # centred on y 820 (between the captions)
            if i < 8:
                flash(canvas, 0.5 * (1.0 - i / 8.0))
            return canvas
        return draw

    # source boxes are 2880x1620 hub pixels, each about 4:3 so the panel is ~780 px tall (y 430..1210)
    segs = [
        (132, push("hub", 200, (0, 0, 2880, 1620), (780, 150, 2880, 1620))),
        (120, push("character", 10, (330, 220, 2650, 1580), (330, 330, 1700, 1500))),
        (126, push("skills", 10, (300, 450, 2700, 1620), (380, 470, 1900, 1580))),
        (120, push("tailor", 10, (150, 140, 2730, 1620), (150, 260, 1700, 1600))),
    ]
    end_n = 102

    def end_seg(i, n):
        return end_card(i / FPS + 0.25, n / FPS)

    total = sum(n for n, _ in segs)
    labels = [("การ์ดของฉัน", "My cards"), ("อุปกรณ์", "Gear"), ("ต้นไม้สกิล", "Skill tree"), ("ช่างตัดเสื้อ", "Tailor")]
    caps = [Caption("โลกลายเส้นหมึก", "A hand-inked world", 0.2, total / FPS - 0.05, 236)]
    # (the panels are centred on y 820 and never taller than ~600 px: the title band above them stays clear)
    t = 0
    for (n, _), (th, en) in zip(segs, labels):
        caps.append(Caption(th, en, t / FPS + 0.1, (t + n) / FPS - 0.05, 1350, fade=0.15, th_size=60, en_size=34))
        t += n
    run_segments("clip4_hub_tour", segs + [(end_n, end_seg)], caps, still_at=132 + 60, music=MUSIC["hub"])


# ------------------------------------------------------------------ clip 5: the Tailor, the card changes live
def clip5():
    """The Tailor (3840x2160 capture): the live character on top, the tapped choices below (a panel that pans to each
    tap), then a cut to the hub card wearing the new look, the end card."""
    tm = manifest_cache["tailor"]["shots"]
    sh = tm["tailor"]
    wx, wy, ww, wh = sh["window"]
    portrait_box = (wx + 8, wy + 8, wx + ww - 8, wy + ww * 0.80)  # head + torso of the live character
    pw = 840
    ow, oh = 1040, 340
    src_w = 1500  # three choice columns from the panel's left edge (no button cut), wheel + Apply fit
    src_h = src_w * oh / ow
    fx0, fy0, fw = sh["cats"][0], sh["cats"][1], sh["cats"][2]
    left_cx = fx0 - 30 + src_w / 2
    right_cx = fx0 + fw + 30 - src_w / 2
    y_lo = fy0 - 30 + src_h / 2
    ev = sh["events"]
    wheel = sh["wheel"]
    downs = [(f, x, y) for f, x, y, s in sh["touches"] if s == 1]
    keys = []
    for f, x, y in downs:
        cx = left_cx if x < left_cx + src_w / 2 - 80 else min(x, right_cx)  # the Makeup tab: pan right
        cy = max(y, y_lo)
        if ev["hair_color"] <= f < ev["eyes_tab"]:
            cy = wheel[1] + wheel[3] / 2  # the colour wheel with Apply / Default
        keys.append((f, cx, cy))
    def focus(f):
        cx, cy = keys[0][1], keys[0][2]
        for kf, kx, ky in keys:
            a = ease((f - (kf - 26)) / 22.0)
            cx, cy = cx + (kx - cx) * a, cy + (ky - cy) * a
        return cx, cy

    t0 = 0
    tailor_n = min(sh["frames"], sh["events"]["final_hair"] + 60)
    portrait_top = 430

    def tailor_seg(i, n):
        f = t0 + i
        img = frame("tailor", "tailor", f)
        canvas = blurred_fill(img, cx=wx + ww / 2).convert("RGBA")
        pmap = panel(canvas, img, portrait_box, pw, portrait_top)
        p_bottom = portrait_top + (portrait_box[3] - portrait_box[1]) * pmap[2]
        cx, cy = focus(f)
        box = (cx - src_w / 2, cy - src_h / 2, cx + src_w / 2, cy + src_h / 2)
        omap = panel(canvas, img, box, ow, p_bottom + 26)
        state = touches_at(sh["touches"], f)
        if state:
            finger(canvas, omap[0] + state[0] * omap[2], omap[1] + state[1] * omap[2])
        for tf, x, y in downs:
            tap_ring(canvas, omap[0] + x * omap[2], omap[1] + y * omap[2], (f - tf) / 30.0)
        return canvas

    cm = tm["card"]
    rect = cm["card"]
    zoom = 1.05
    ccx, ccy = rect[0] + rect[2] / 2, 940
    x0, y0 = ccx - W / zoom / 2, ccy - H / zoom / 2
    zrect = [(rect[0] - x0) * zoom, (rect[1] - y0) * zoom, rect[2] * zoom, rect[3] * zoom]
    card_n = 100  # ~1.6 s of the final look on the card (Boss: hold ~1.5 s before the end card)

    def card_seg(i, n):
        canvas = card_frame_run("tailor", "card", i, zoom, (ccx, ccy))
        if 6 <= i <= 36:
            glint(canvas, zrect, (i - 6) / 30.0)
        if i < 10:
            flash(canvas, 0.6 * (1.0 - i / 10.0), (255, 240, 205))
        return canvas

    end_n = 130

    def end_seg(i, n):
        canvas = end_card(i / FPS + 0.25, n / FPS)
        if i < 10:
            canvas = Image.blend(card_frame_run("tailor", "card", card_n - 1, zoom, (ccx, ccy)), canvas, i / 10)
        return canvas

    t_cut = tailor_n / FPS
    caps = [
        Caption("แต่งตัวละครได้ตามใจ", "Dress your hero your way", 0.25, t_cut - 0.05, 236),
        Caption("การ์ดเปลี่ยนตามทันที", "The card changes instantly", t_cut + 0.1, t_cut + card_n / FPS - 0.05, 236),
    ]
    run_segments("clip5_tailor", [(tailor_n, tailor_seg), (card_n, card_seg), (end_n, end_seg)], caps,
                 still_at=tailor_n + 60, music=MUSIC["hub"])


def card_frame_run(run, shot, n, zoom, centre):
    img = frame(run, shot, n)
    img, _ = window(img, centre[0], centre[1], W / zoom)
    return img.convert("RGBA")


def main():
    for run in ["card", "battle", "hub", "tailor"]:
        if (FRAMES / run / "manifest.json").exists():
            manifest_cache[run] = manifest(run)
    wanted = sys.argv[1:] or ["clip1", "clip2", "clip3", "clip4"]
    for name in wanted:
        globals()[name]()


if __name__ == "__main__":
    main()
