import math
from PIL import Image

img = Image.open(r"d:\zhanji\moshi_demo\tests\out\bat_bullet.png").convert("RGB")
W, H = img.size
cam = (1500.0, 1410.0)
zoom = 0.72
bullet = (1643.843, 1486.303)
d = (-0.995495, 0.094809)
bg = img.getpixel((8, H - 8))


def to_screen(p):
    return ((p[0] - cam[0]) * zoom + W / 2.0, (p[1] - cam[1]) * zoom + H / 2.0)


bx, by = to_screen(bullet)
print("bullet screen", round(bx, 1), round(by, 1), "bg", bg)

# 沿飞行轴采样：along > 0 = 前方（弹头该在的地方），< 0 = 后方（拖尾/残影）
n = (-d[1], d[0])
print("along  |  横切剖面（|=中轴）      max_diff")
for along in range(80, -121, -10):
    row = []
    best = 0
    for off in range(-30, 31, 3):
        x = bx + d[0] * along * zoom + n[0] * off
        y = by + d[1] * along * zoom + n[1] * off
        if 0 <= x < W and 0 <= y < H:
            px = img.getpixel((int(x), int(y)))
            diff = sum(abs(a - b) for a, b in zip(px, bg))
            best = max(best, diff)
            row.append("#" if diff > 150 else ("+" if diff > 80 else (":" if diff > 30 else ".")))
        else:
            row.append(" ")
    print("%5d  %s   %d" % (along, "".join(row), best))
