class_name PlayerConfig
extends Resource
## 人物总表。人物的血量、冲刺斩、表盘行动点、回溯、笔墨消耗、五道神纹的数值，
## 全部收在这一份 res://data/player.tres 里，编辑器双击打开，Inspector 里改完存盘即生效。
##
## 结构：
##   生存     → 血量 / 受击无敌 / 接触伤害倍率
##   冲刺斩   → 左键表盘斩与右键笔画斩共用的速度、距离、半径、伤害
##   表盘     → 行动点上限与回复速率
##   回溯     → 钟表充能、回溯格数、伤害倍率、标记保留
##   笔墨     → 时间之力上限/回复、**每像素墨耗**、子弹时间流逝
##   觉醒     → 点亮空碑的门槛与概率
##   神纹     → 五道技能各自的冷却与效果参数
##
## **想画更长的线** → 把「笔墨」组的 tv_cost_per_px 调小（1 px 消耗多少墨，越小画得越长），
## 或把 tv_max_base 调大、bullet_tv_drain 调小（子弹时间每秒的额外流逝）。
##
## 怪物那边的数值在 res://data/balance.tres（BalanceConfig），
## 施法的识别门槛（笔多长算数、画多像才认）在 res://data/spell.tres（SpellConfig），三份表互不重叠。
## 详见 docs/player.md。

const PATH := "res://data/player.tres"

# ============================== 生存 ==============================

@export_group("生存")
## 人物最大血量。归零直接结算（时滞/复活已移除）。
@export var player_hp: float = 100.0
## 撞到怪身上时受到的伤害倍率。怪的基础伤害是 balance.tres 里每只怪的 dmg，
## 这里乘一道系数：0.5 = 挨撞只掉一半，0 = 撞不死人。
@export var contact_dmg_mult: float = 1.0
## 敌弹命中时的伤害倍率。同上，乘在弹的 bullet_dmg 上。
@export var bullet_dmg_mult: float = 1.0
## 挨一下之后的无敌时间（秒）。越大越吃得住连续挨打。
@export var hit_invuln: float = 0.6
## 挨打扣掉的钟表充能（秒）。**默认 0 = 挨打不掉 R 的充能进度**，
## 想恢复「受伤打断蓄力」的手感就填回 3.0。
@export var hit_charge_penalty: float = 0.0
## 挨打扣掉的分数倍率。
@export var hit_mult_penalty: float = 0.2

# ============================== 冲刺斩 ==============================

@export_group("冲刺斩")
## 沿轨迹推进的速度（像素/秒）。只管冲得多快，不影响落点。
@export var dash_speed: float = 3200.0
## 左键表盘斩的基础距离（像素）。这就是「一刀能冲多远」。
@export var dash_dist_base: float = 520.0
## 表盘斩距离的成长上限（像素）。局外养成加得再多也不超它。
@export var dash_dist_cap: float = 800.0
## 冲刺沿途的命中半径（像素）。调大即变好打。
@export var dash_radius: float = 140.0
## 冲刺沿途挂的标记伤害。回溯重放按 rewind_mult 打折。
@export var dash_dmg: float = 20.0
## 冲刺结束后的无敌时间（秒）。
@export var post_dash_invuln: float = 0.3
## 两次左键斩之间的最小间隔（秒），防连点。
@export var slash_min_gap: float = 0.15

# ============================== 表盘 / 行动点 ==============================

@export_group("表盘")
## 行动点上限。1 点 = 一次左键斩。
@export var ap_max_base: int = 3
## 行动点上限的成长天花板。
@export var ap_max_cap: int = 6
## 时针转一圈的秒数。同时决定左键斩的朝向变化快慢。每秒一圈 = 每秒回 1 AP。
@export var hour_period: float = 1.0
## 时针转一圈回多少行动点。
@export var ap_per_hour: float = 1.0
## 秒针周期（秒），买了指针升级才生效。
@export var sec_period: float = 0.5
## 秒针转一圈回多少行动点。
@export var ap_per_sec: float = 0.25
## 分针周期（秒），买了二级指针升级才生效。
@export var min_period: float = 1.0
## 分针转一圈回多少行动点。
@export var ap_per_min: float = 0.25

# ============================== 回溯 ==============================

@export_group("回溯")
## 钟表充满需要多少秒。充满后按 R 可以回溯。
@export var clock_time: float = 12.0
## 回溯能重放最近几条轨迹。
@export var rewind_slots: int = 5
## 回溯重放时的伤害倍率（乘在 dash_dmg 上）。
@export var rewind_mult: float = 0.5
## 回溯重放单条轨迹的时长（秒）。
@export var rewind_path_time: float = 0.15
## 引爆结算的顿帧时长（秒）。
@export var burst_freeze: float = 0.16
## 标记保留时长（秒）。超过这个时间没引爆，标记伤害就重新计。
@export var mark_retain: float = 1.5

# ============================== 笔墨（时间之力） ==============================

@export_group("笔墨")
## 时间之力上限，也就是「一管墨」有多少。1 墨 = 1 px 笔画。
## 注意 `Game.tv_max()` 还压着一条成长封顶 1000，填更大的数不会生效。
@export var tv_max_base: float = 1000.0
## 时间之力每秒回复量（只在非书写状态回）。
@export var tv_regen_base: float = 240.0
## **每画 1 像素消耗多少墨。调小就能画更长的线**，调到 0 等于无限长。
@export var tv_cost_per_px: float = 1.0
## 子弹时间倍率：书写期间怪物按这个倍速行动。越小越慢。
@export var bullet_factor: float = 0.10
## 子弹时间每秒额外流逝的墨（不画也在烧）。
@export var bullet_tv_drain: float = 30.0
## 进入书写后至少维持多久才允许因墨尽自动收笔（秒）。
@export var bullet_min_time: float = 0.2
## 墨低于这个值就起不了笔 / 自动收笔。
@export var bullet_exit_tv: float = 10.0

# ============================== 觉醒 ==============================

@export_group("觉醒")
## 点亮空碑的门槛：这一笔要烧掉起笔时余额的这么多比例（含子弹时间流逝）。
@export var bind_energy_ratio: float = 0.70
## 过门槛之后的触发概率。
@export var bind_chance: float = 0.50

# ============================== 神纹 ==============================

@export_group("神纹")

@export_subgroup("雷霆万钧")
@export var thunder_cd: float = 6.0
## 随机劈几个目标。
@export var thunder_bolts: int = 6
@export var thunder_dmg: float = 20.0
## 每道雷的溅射半径。
@export var thunder_radius: float = 82.0

@export_subgroup("山崩地裂")
@export var quake_cd: float = 12.0
## 跟着人物走的地震轮数。
@export var quake_waves: int = 6
## 两轮之间的间隔（秒）。
@export var quake_gap: float = 0.5
@export var quake_radius: float = 155.0
@export var quake_dmg: float = 12.0

@export_subgroup("妖木精灵")
@export var ent_cd: float = 20.0
## 召出几个树人。
@export var ent_count: int = 4
## 树人存活时长（秒）。
@export var ent_life: float = 12.0
@export var ent_speed: float = 155.0
## 树人的攻击距离。
@export var ent_reach: float = 44.0
@export var ent_dmg: float = 10.0
## 树人两次攻击的间隔（秒）。
@export var ent_gap: float = 0.7

@export_subgroup("水漫金山")
@export var flood_cd: float = 10.0
## 推出几道水浪（均分一圈）。
@export var flood_dirs: int = 8
@export var flood_speed: float = 540.0
## 水浪推进的总距离。
@export var flood_range: float = 640.0
## 水浪的半宽，命中判定按它算。
@export var flood_width: float = 34.0
@export var flood_dmg: float = 16.0

@export_subgroup("无限剑阵")
@export var swords_cd: float = 14.0
## 内圈剑数。
@export var sword_inner: int = 6
## 外圈剑数。
@export var sword_outer: int = 12
@export var sword_r_in: float = 115.0
@export var sword_r_out: float = 245.0
## 单剑下落时长（秒）。
@export var sword_fall: float = 0.4
@export var sword_radius: float = 58.0
@export var sword_dmg: float = 22.0

## 按技能 id 取冷却。id 对不上返回 -1，调用方保留神纹录里的原值。
func skill_cd(id: String) -> float:
	match id:
		"thunder":
			return thunder_cd
		"quake":
			return quake_cd
		"ent":
			return ent_cd
		"flood":
			return flood_cd
		"swords":
			return swords_cd
	return -1.0

static var _inst: PlayerConfig = null

## 取全局唯一实例。加载不到就退回一份代码默认值，保证不崩。
static func get_config() -> PlayerConfig:
	if _inst == null:
		var res := ResourceLoader.load(PATH)
		if res is PlayerConfig:
			_inst = res
		else:
			push_error("PlayerConfig: 加载不到 %s —— 导出包请确认 data/ 已打进资源过滤器" % PATH)
			_inst = PlayerConfig.new()
	return _inst

## 重新从磁盘读一遍。
static func reload() -> PlayerConfig:
	_inst = null
	var res := ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if res is PlayerConfig:
		_inst = res
	return get_config()
