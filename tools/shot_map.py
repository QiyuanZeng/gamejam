from PIL import Image

img = Image.open(r"d:\zhanji\moshi_demo\tests\out\bat_bullet.png").convert("RGB")
W, H = img.size
bg = img.getpixel((8, H - 8))
print("size", W, H, "bg", bg)

step = 12
for y in range(0, H, step):
    row = []
    for x in range(0, W, step):
        px = img.getpixel((x, y))
        d = sum(abs(a - b) for a, b in zip(px, bg))
        row.append("#" if d > 150 else ("+" if d > 80 else (":" if d > 30 else ".")))
    print("%4d %s" % (y, "".join(row)))
