class_name InkBrushStyle
extends Resource
## 水墨笔触样式（可序列化效果文件）。
## 保存位置：user://ink_style.tres（玩家改动）覆盖 res://ink_style.tres（默认预设）。

@export_group("墨带宽")
@export var width_start := 13.0        ## 起笔宽
@export var width_end := 1.6           ## 收锋宽
@export var width_taper := 0.8         ## 衰减指数（大=快收锋）
@export var width_wobble_amp := 0.9    ## 墨量波动幅度
@export var width_wobble_freq := 26.0  ## 墨量波动频率

@export_group("墨色")
@export var ink_color := Color("#1A1714")     ## 墨色
@export var red_color := Color("#C0392B")     ## 回溯朱红
@export var paper_color := Color("#F5F1E8")   ## 纸色（飞白透底色）
@export var body_alpha := 0.92                ## 主体浓淡
@export var halo_scale := 1.5                 ## 晕边宽度倍率
@export var halo_alpha := 0.16                ## 晕边浓淡

@export_group("轮廓")
@export var edge_jitter := 0.18        ## 主体轮廓毛糙
@export var halo_jitter := 0.25        ## 晕边毛糙
@export var smooth_iters := 2          ## 平滑迭代（0-4）

@export_group("飞白")
@export var feibai_chance := 0.55      ## 飞白丝出现概率
@export var feibai_step := 3           ## 检测间隔（点）
@export var feibai_alpha := 0.32       ## 飞白强度
@export var feibai_len_min := 6.0
@export var feibai_len_max := 26.0

@export_group("溅墨")
@export var splatter_step := 3
@export var splatter_chance := 0.7
@export var splatter_alpha := 0.55
@export var splatter_size_min := 0.8
@export var splatter_size_max := 3.0
@export var splatter_spread := 12.0

@export_group("收锋")
@export var tail_strands := 5          ## 末端散丝数
@export var tail_len_min := 8.0
@export var tail_len_max := 30.0
@export var tail_spread := 0.5         ## 张角（弧度）
@export var tail_alpha := 0.7

@export_group("渗墨（画布扩散）")
@export var bleed_enabled := 1.0       ## 渗墨开关 0/1
@export var bleed_radius := 1.2        ## 渗墨速度（每帧模糊半径 px，逐帧迭代≈扩散）
@export var bleed_fade := 0.992        ## 每帧消褪系数（1=不褪）
@export var grain_strength := 0.35     ## 纸颗粒吃墨强度
