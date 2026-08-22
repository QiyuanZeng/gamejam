import sys, os
sys.path.insert(0, r"C:\Users\lizhaokun\.claude\skills\gen-image-video\scripts")
from gen_media import request_image

OUT = r"d:\zhanji\moshi_demo\assets"
os.makedirs(OUT, exist_ok=True)

JOBS = [
    ("bg_paper.png", "1536x1024",
     "中国传统宣纸背景纹理，冷调米白色，纸张植物纤维肌理细腻可见，画面中央偏右画有一个巨大的淡墨圆环（禅意円相圆圈），墨色极淡若有若无，圆环边缘有自然的水墨晕染，大量留白，极简水墨风格，无任何文字，无任何角色，无任何杂物"),
    ("player.png", "1024x1024",
     "水墨画风格的无脸兜帽剑客全身剪影，站立姿态，深墨近黑色简笔画，宽大斗篷下摆飘逸拖出几缕墨丝，手持一支毛笔形长刀，腰带处只有一个小小的朱砂红色圆点，背景为纯宣纸米白色，居中构图，单角色全身，简约留白，无文字"),
    ("enemy_blob.png", "1024x1024",
     "水墨画风格的小墨团怪物，不规则圆形墨渍形状，深墨黑色，墨团边缘自然晕染飞白，墨团中央偏上有一只朱砂红色小圆点眼睛，整体是一个圆滚滚的墨滴精灵，背景为纯宣纸米白色，居中构图，单个怪物，简约，无文字"),
    ("enemy_fast.png", "1024x1024",
     "水墨画风格的疾速妖物，向右横向拉长的飞溅墨迹形状，灰墨色，笔触带速度感和飞白，像一道横向的墨色残影，墨迹中央有一颗朱砂红色小圆点眼睛，背景为纯宣纸米白色，居中构图，单个怪物，简约，无文字"),
    ("enemy_tank.png", "1024x1024",
     "水墨画风格的巨大磐石妖，厚重的浓墨巨石团块，纯浓墨剪影风格，整个怪物是均匀的深墨黑色，表面绝无高光、绝无白色或浅灰色斑点，只有少量干笔飞白纹理，体量感庞大如小山，正前方有两颗小小的朱砂红色圆点眼睛，背景为纯宣纸米白色，居中构图，单个怪物，简约，无文字"),
]

only = set(sys.argv[1:])
fails = []
for name, size, prompt in JOBS:
    if only and name not in only:
        continue
    dest = os.path.join(OUT, name)
    if os.path.exists(dest) and os.path.getsize(dest) > 10000:
        print("SKIP", name)
        continue
    try:
        b = request_image(prompt, size=size, poll_timeout=240.0)
        with open(dest, "wb") as f:
            f.write(b)
        print("OK", name, len(b))
    except Exception as ex:
        print("FAIL", name, repr(ex))
        fails.append(name)

print("DONE fails=", fails)
