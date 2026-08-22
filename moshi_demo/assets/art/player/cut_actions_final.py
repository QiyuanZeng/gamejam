from PIL import Image
import os, subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed

# 《动作设计-角色图.png》最终切图管线：
# 网格 = 10列(275.2px) x 5卡片行(图上标签下)，行起点动作 1/7/13/19/25
# 左半 c0-c4 = 25 帧；右半末列 c9 = 12/18/24/30；动作6 取 r1c5（r1c9 备选）
# 管线：裁艺术区(避开下方标签) -> DreamMaker rembg 抠图 -> alpha 包围盒精裁 -> 方形补边 -> 256x256

SRC = r'c:\Users\N32955\Desktop\NetEase网易互娱\00_GameJam比赛\0-美术图\动作设计-角色图.png'
OUT = r'c:\Users\N32955\Desktop\NetEase网易互娱\00_GameJam比赛\gamejam-godot\moshi_demo\assets\art\player\actions'
TMP = r'c:\Users\N32955\Desktop\NetEase网易互娱\00_GameJam比赛\gamejam-godot\moshi_demo\assets\art\player\_tmp_actions'
REMBG = r'C:\Users\N32955\.codemaker\skills\dreammaker-image-gen\scripts\rembg.js'

os.makedirs(OUT, exist_ok=True)
os.makedirs(TMP, exist_ok=True)

img = Image.open(SRC).convert('RGBA')
w, h = img.size
cw = w / 10.0

# (动作号, 英文名, 行, 列)
CARDS = [
    (1, 'idle',          0, 0), (2, 'run_start',    0, 1), (3, 'dash',        0, 2), (4, 'jump_slash',  0, 3), (5, 'slash_h',     0, 4),
    (6, 'thrust',        0, 5),
    (7, 'charge',        1, 0), (8, 'heavy_slash',  1, 1), (9, 'slash_low',   1, 2), (10, 'wave_slash', 1, 3), (11, 'combo_spin', 1, 4),
    (12, 'thrust_final', 1, 9),
    (13, 'windball_cast',   2, 0), (14, 'windball_float',  2, 1), (15, 'windball_spread', 2, 2), (16, 'windball_fire',  2, 3), (17, 'windball_hit',   2, 4),
    (18, 'windball_fade',   2, 9),
    (19, 'dash_fast',    3, 0), (20, 'stop',        3, 1), (21, 'turn',       3, 2), (22, 'step_back',  3, 3), (23, 'dodge_roll',  3, 4),
    (24, 'dodge_slide',  3, 9),
    (25, 'spin',         4, 0), (26, 'spin_air',    4, 1), (27, 'blade_orbit', 4, 2), (28, 'blade_spread', 4, 3), (29, 'blade_burst', 4, 4),
    (30, 'ult_end',      4, 9),
]
# 备选：动作6 另一候选位 r1c9
ALT = (6, 'thrust_alt', 0, 9)

# 每行艺术区 y 边界（像素分析：art 带上下加边距，避开底部标签带）
ROW_ART = [
    (140, 350),   # r0: art 156-300, label 362-384
    (500, 685),   # r1: art 521-662, label 699-721
    (770, 958),   # r2: art 790-952, label 971-994
    (1055, 1198), # r3: art 1072-1184, label 1211-1233
    (1288, 1452), # r4: art 1303-1434, label 1465-1487
]

def crop_card(row, col):
    x0, x1 = int(col * cw), int((col + 1) * cw)
    y0, y1 = ROW_ART[row]
    return img.crop((x0, y0, x1, y1))

def rembg(in_path, out_path):
    r = subprocess.run(['node', REMBG, in_path, out_path], capture_output=True, text=True, timeout=120)
    return r.returncode == 0 and os.path.exists(out_path), (r.stderr or r.stdout or '')[-200:]

def alpha_trim(im, pad_ratio=0.06):
    bbox = im.getbbox()  # 非零像素包围盒
    if bbox is None:
        return im
    im = im.crop(bbox)
    side = max(im.width, im.height)
    pad = int(side * pad_ratio)
    canvas = Image.new('RGBA', (side + pad * 2, side + pad * 2), (0, 0, 0, 0))
    canvas.paste(im, ((canvas.width - im.width) // 2, (canvas.height - im.height) // 2), im)
    return canvas

def process_one(num, name, row, col):
    raw = os.path.join(TMP, f'{num:02d}_{name}_raw.png')
    cut = os.path.join(TMP, f'{num:02d}_{name}_cut.png')
    crop_card(row, col).save(raw)
    ok, err = rembg(raw, cut)
    if not ok:
        return (num, name, False, err)
    fin = Image.open(cut).convert('RGBA')
    fin = alpha_trim(fin)
    fin = fin.resize((256, 256), Image.Resampling.LANCZOS)
    fin.save(os.path.join(OUT, f'act_{num:02d}_{name}.png'))
    return (num, name, True, '')

jobs = CARDS + [ALT]
failed = []
with ThreadPoolExecutor(max_workers=8) as pool:
    futures = {pool.submit(process_one, *j): j for j in jobs}
    for f in as_completed(futures):
        num, name, ok, err = f.result()
        if ok:
            print(f'OK act_{num:02d}_{name}.png')
        else:
            print(f'FAIL {num:02d}_{name}: {err}')
            failed.append((num, name, err))

print(f'\nDone. success={len(jobs) - len(failed)}, failed={len(failed)}')
