from PIL import Image
import os

img = Image.open(r'c:\Users\N32955\Desktop\NetEase网易互娱\00_GameJam比赛\0-美术图\动作设计-顶视图.png')
w, h = img.size
cols, rows = 6, 5
fw, fh = w // cols, h // rows
print(f'Image: {w}x{h}, Frame: {fw}x{fh}')

out_dir = r'c:\Users\N32955\Desktop\NetEase网易互娱\00_GameJam比赛\墨时_demo\assets\art\player\temp_frames'
os.makedirs(out_dir, exist_ok=True)

for r in range(rows):
    for c in range(cols):
        idx = r * cols + c
        box = (c * fw, r * fh, (c + 1) * fw, (r + 1) * fh)
        frame = img.crop(box)
        frame.save(os.path.join(out_dir, f'frame_{idx:02d}.png'))

print(f'Done: {rows * cols} frames saved to {out_dir}')
