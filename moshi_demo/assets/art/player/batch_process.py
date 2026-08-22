from PIL import Image
import os
import subprocess
import sys

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
    
    print(f'\n=== Processing frame_{idx:02d} ===')
    
    # Step 1: 裁掉顶部 25%（文字区）
    img = Image.open(src_path)
    w, h = img.size
    crop_top = int(h * 0.25)
    img = img.crop((0, crop_top, w, h))
    cropped_path = os.path.join(out_dir, f'frame_{idx:02d}_cropped.png')
    img.save(cropped_path)
    print(f'  Step 1: Cropped top 25% -> {cropped_path}')
    
    # Step 2: DreamMaker rembg 抠图
    rembg_path = os.path.join(out_dir, f'frame_{idx:02d}_rembg.png')
    print(f'  Step 2: Running DreamMaker rembg...')
    result = subprocess.run(
        ['node', r'C:\Users\N32955\.codemaker\skills\dreammaker-image-gen\scripts\rembg.js', cropped_path, rembg_path],
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        print(f'  ❌ rembg failed: {result.stderr}')
        continue
    print(f'  ✅ rembg done -> {rembg_path}')
    
    # Step 3: 缩放到 256×256
    img = Image.open(rembg_path).convert('RGBA')
    img = img.resize((256, 256), Image.Resampling.LANCZOS)
    final_path = os.path.join(out_dir, f'idle_{idx:02d}.png')
    img.save(final_path)
    print(f'  Step 3: Resized to 256x256 -> {final_path}')

print(f'\n=== Done: {len(frame_indices)} frames processed ===')
