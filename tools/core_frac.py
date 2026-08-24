import glob
from PIL import Image

for p in sorted(glob.glob(r"d:\zhanji\moshi_demo\assets\art\enemies\bat_enemy\effects\projectile_fly\*.png")):
    im = Image.open(p).convert("RGBA")
    W, H = im.size
    px = im.load()
    sw = sx = sy = 0.0
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if a < 40:
                continue
            lum = (0.3 * r + 0.6 * g + 0.1 * b) * (a / 255.0) / 255.0
            w = lum ** 3
            sw += w
            sx += x * w
            sy += y * w
    print("%-24s %dx%d  core_x=%.3f core_y=%.3f" % (p.rsplit("\\", 1)[-1], W, H, sx / sw / W, sy / sw / H))
