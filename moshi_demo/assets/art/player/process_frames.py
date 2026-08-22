from PIL import Image
import os

src_dir = r'c:\Users\N32955\Desktop\NetEase网易互娱\00_GameJam比赛\墨时_demo\assets\art\player\temp_frames'
out_dir = r'c:\Users\N32955\Desktop\NetEase网易互娱\00_GameJam比赛\墨时_demo\assets\art\player\idle'
os.makedirs(out_dir, exist_ok=True)

# 只取前 8 帧做待机动画
frame_indices = [0, 1, 2, 3, 4, 5, 6, 7]

for idx in frame_indices:
    src_path = os.path.join(src_dir, f'frame_{idx:02d}.png')
    if not os.path.exists(src_path):
        print(f'Skip: {src_path} not found')
        continue
    
    img = Image.open(src_path).convert('RGBA')
    w, h = img.size
    
    # 裁掉顶部 25%（文字区）
    crop_top = int(h * 0.25)
    img = img.crop((0, crop_top, w, h))
    
    # 抠米色背景（亮度 > 0.85 的像素变透明）
    pixels = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = pixels[x, y]
            lum = (r * 0.299 + g * 0.587 + b * 0.114) / 255.0
            if lum > 0.85:
                pixels[x, y] = (r, g, b, 0)
    
    # 缩放到 256×256
    img = img.resize((256, 256), Image.Resampling.LANCZOS)
    
    # 保存
    out_path = os.path.join(out_dir, f'idle_{idx:02d}.png')
    img.save(out_path)
    print(f'Saved: {out_path}')

print(f'Done: {len(frame_indices)} frames processed')
