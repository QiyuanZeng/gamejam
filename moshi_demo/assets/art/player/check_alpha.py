from PIL import Image
import os

# 检查 idle_00 的像素分布
path = r'c:\Users\N32955\Desktop\NetEase网易互娱\00_GameJam比赛\墨时_demo\assets\art\player\idle\idle_00.png'
img = Image.open(path)
print(f'Size: {img.size}, Mode: {img.mode}')

if img.mode == 'RGBA':
    px = img.load()
    transparent = 0
    dark = 0
    bright = 0
    total = img.width * img.height
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a == 0:
                transparent += 1
            else:
                lum = (r * 0.299 + g * 0.587 + b * 0.114) / 255.0
                if lum < 0.2:
                    dark += 1
                elif lum > 0.8:
                    bright += 1
    print(f'透明: {transparent} ({transparent/total*100:.1f}%)')
    print(f'暗色(alpha>0): {dark} ({dark/total*100:.1f}%)')
    print(f'亮色(alpha>0): {bright} ({bright/total*100:.1f}%)')
