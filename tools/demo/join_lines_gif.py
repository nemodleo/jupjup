# README용 "한 줄로 잇기" GIF. 알림은 앱이 그린 것(Jupjup -snapshot <폴더> → demo-*.png)을 그대로 쓰고, PDF 종이·고르기 틀·붙여넣기 상자만 여기서 그린다.
# python3 tools/demo/join_lines_gif.py <스냅샷 폴더> <출력 폴더>  → join-lines.gif(영어), join-lines.ko.gif
import sys, math
from PIL import Image, ImageDraw, ImageFont
SNAP, OUT = sys.argv[1], sys.argv[2]
W, H = 1520, 960            # 2x 작업 → 760×480 GIF
INK, HANJI, SEAL, SUB, FAINT = (31,29,26), (228,221,207), (196,85,58), (74,68,60), (107,100,90)
SD = '/System/Library/Fonts/AppleSDGothicNeo.ttc'
SERIF = '/System/Library/Fonts/Supplemental/Times New Roman.ttf'
SYM = ImageFont.truetype('/System/Library/Fonts/Apple Symbols.ttf', 36)
f = lambda s, w=0: ImageFont.truetype(SD, s, index=w)
serif = lambda s: ImageFont.truetype(SERIF, s)
LINES = ["We propose a method that recovers tables from screen pixels by finding ver-",
         "tical gutters shared by every row. Unlike prior work, it needs no layout model",
         "and runs on-device in under a second. On a benchmark of 8 rendered tables",
         "it reaches 98% cell accuracy."]
JOINED = "We propose a method that recovers tables from screen pixels by finding vertical gutters shared by every row. Unlike prior work, it needs no layout model and runs on-device in under a second. On a benchmark of 8 rendered tables it reaches 98% cell accuracy."
T = {
 'ko': dict(step1="PDF에서 여러 줄을 그냥 복사하면", step1b="줄바꿈이 섞여 들어와요", step2="줍줍 · ⇧⌘2로 고르기", step3="알림에서 한 줄로 잇기", step4="붙여넣으면 한 줄", normal="일반 복사 → 붙여넣기", jj="줍줍 → 붙여넣기"),
 'en': dict(step1="Copy a few lines from a PDF", step1b="and you get the line breaks too", step2="Jupjup · select with ⇧⌘2", step3="Join Lines in the notification", step4="Paste: one line", normal="Plain copy → paste", jj="Jupjup → paste"),
}
PAGE = (60, 150, 830, 700)   # PDF 종이
PARA_Y = 330                 # 문단 첫 줄 y
LH = 46
def page(d):
    d.rounded_rectangle(PAGE, 6, fill=(255,255,255), outline=(200,196,188))
    d.text((PAGE[0]+60, 190), "3  Method", font=serif(34), fill=INK)
    d.text((PAGE[0]+60, 250), "3.1  Finding gutters", font=serif(26), fill=INK)
    for i, l in enumerate(LINES):
        d.text((PAGE[0]+60, PARA_Y + i*LH), l, font=serif(22), fill=INK)
    d.text((PAGE[0]+60, PARA_Y + 4*LH + 30), "Table 1 reports accuracy per case; Figure 2 shows failure modes.", font=serif(22), fill=(150,146,138))
def para_rect(frac=1.0):
    x0, y0 = PAGE[0]+44, PARA_Y-10
    x1, y1 = PAGE[0]+745, PARA_Y + 4*LH + 2
    return (x0, y0, x0 + (x1-x0)*min(1, frac*1.15), y0 + (y1-y0)*frac)
def brackets(d, r, dim=True, phase=0):
    x0,y0,x1,y1 = r; L = 34; w = 5
    for (x,y,sx,sy) in [(x0,y0,1,1),(x1,y0,-1,1),(x0,y1,1,-1),(x1,y1,-1,-1)]:
        d.line([(x, y+sy*L),(x,y),(x+sx*L,y)], fill=SEAL, width=w)
    # 점선 테두리
    n = 0
    for (a,b) in [((x0,y0),(x1,y0)),((x1,y0),(x1,y1)),((x0,y1),(x1,y1)),((x0,y0),(x0,y1))]:
        length = math.hypot(b[0]-a[0], b[1]-a[1]); t = (phase % 18)
        while t < length:
            u0, u1 = t/length, min(1,(t+10)/length)
            d.line([(a[0]+(b[0]-a[0])*u0, a[1]+(b[1]-a[1])*u0),(a[0]+(b[0]-a[0])*u1, a[1]+(b[1]-a[1])*u1)], fill=SEAL, width=2)
            t += 18
def cursor(d, x, y):
    pts = [(x,y),(x,y+30),(x+8,y+23),(x+13,y+34),(x+19,y+31),(x+14,y+21),(x+23,y+21)]
    d.polygon(pts, fill=(0,0,0), outline=(255,255,255))
def paste_box(d, x, y, w, mode, t):
    fn = f(22)
    d.rounded_rectangle((x, y, x+w, y+300), 10, fill=(255,255,255), outline=(200,196,188))
    d.text((x+22, y+16), t['normal'] if mode=='normal' else t['jj'], font=f(24,1), fill=FAINT if mode=='normal' else SEAL)
    if mode == 'normal':
        for i, l in enumerate(LINES):
            s2 = l
            while fn.getlength(s2) > w-90: s2 = s2[:-2] + "…"
            d.text((x+22, y+62+i*38), s2, font=fn, fill=INK)
            d.text((x+22+fn.getlength(s2)+10, y+54+i*38), "⏎", font=SYM, fill=SEAL)
    else:
        words, line, yy = JOINED.split(" "), "", y+62
        for wd in words:
            if fn.getlength(line + " " + wd) > w-44: d.text((x+22, yy), line, font=fn, fill=INK); line, yy = wd, yy+36
            else: line = (line + " " + wd).strip()
        d.text((x+22, yy), line, font=fn, fill=INK)
        d.rectangle((x+22+fn.getlength(line)+6, yy+2, x+22+fn.getlength(line)+9, yy+28), fill=INK)
def frame(lang, stage, k, cur=None, toast=None, sel=None, phase=0):
    t = T[lang]
    im = Image.new('RGB', (W, H), HANJI); d = ImageDraw.Draw(im)
    page(d)
    cap = {1: t['step1'], 2: t['step2'], 3: t['step3'], 4: t['step4']}[stage]
    d.text((60, 60), cap, font=f(40,2), fill=INK)
    if stage == 1: d.text((60+f(40,2).getlength(cap)+24, 70), t['step1b'], font=f(30), fill=SUB)
    if sel: brackets(d, sel, phase=phase)
    paste_box(d, 870, 540, 600, 'normal' if stage < 4 else 'jj', t)
    if toast:
        tim = Image.open(f'{SNAP}/demo-{lang}-{toast}.png').convert('RGBA')
        im.paste(tim, (W - tim.width - 20, 110), tim)
    if cur: cursor(d, *cur)
    return im
def build(lang):
    frames, dur = [], []
    def add(im, ms): frames.append(im); dur.append(ms)
    add(frame(lang, 1, 0), 1400)
    r1 = para_rect(1); x0,y0 = r1[0], r1[1]
    for i in range(1, 9):                           # 끌어서 고르기
        fr = i/8; r = para_rect(fr); add(frame(lang, 2, i, cur=(r[2], r[3]), sel=r), 80)
    for i in range(6): add(frame(lang, 2, i, cur=(r1[2], r1[3]), sel=r1, toast='working', phase=i*4), 110)
    # 담김 → 커서가 "한 줄로 잇기"로
    bx, by = W-20-672+268, 110+214
    sx, sy = r1[2], r1[3]
    for i in range(1, 9):
        u = i/8; add(frame(lang, 3, i, cur=(sx+(bx-sx)*u, sy+(by-sy)*u), toast='picked'), 90 if i<8 else 500)
    add(frame(lang, 3, 9, cur=(bx, by), toast='joined'), 900)
    add(frame(lang, 4, 10, cur=(bx, by), toast='joined'), 2600)
    small = [im.resize((W//2, H//2), Image.LANCZOS) for im in frames]
    out = f'{OUT}/join-lines{"" if lang=="en" else "."+lang}.gif'
    small[0].save(out, save_all=True, append_images=small[1:], duration=dur, loop=0, optimize=True)
    frames[-1].resize((W//2, H//2), Image.LANCZOS).save(f'{OUT}/check-{lang}-last.png'); frames[12].resize((W//2, H//2), Image.LANCZOS).save(f'{OUT}/check-{lang}-mid.png')
    import os; print(out, os.path.getsize(out)//1024, 'KB', len(frames), 'frames')
for lang in ('ko', 'en'): build(lang)
