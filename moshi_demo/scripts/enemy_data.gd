class_name EnemyData
extends Resource
## 怪物配置资源。全部怪物收在 res://data/balance.tres 的 enemies 数组里，
## 编辑器双击那份总表，展开对应的一项就能改数值。
## 换模型 → 改 tex / anim_dir；换数值 → 改本资源对应字段；换行为 → 改 behavior。
## 详见 docs/enemies.md。

## 行为分类。决定 Enemy 每帧走哪条移动/攻击分支。
enum Behavior {
	MELEE,    ## 近战小兵：直追玩家，仅触碰伤害
	RANGED,   ## 远程小兵：到攻击距离停步开火，子弹可被玩家技能销毁
	CHARGER,  ## 冲锋小兵：到冲锋距离停步蓄力，蓄满后直线冲刺
	SPLITTER, ## 分裂怪：行为同近战，死亡时分裂出小体
	BOSS,     ## BOSS：多阶段，复用上述行为组合
}

# ── 身份 ────────────────────────────────────────────────────────────
@export var id: String = ""                    ## 唯一 id，刷怪表与分裂引用它
@export var display_name: String = ""          ## 中文名，仅用于展示/调试
@export var behavior: Behavior = Behavior.MELEE

# ── 基础数值 ────────────────────────────────────────────────────────
@export_group("数值")
@export var hp: float = 10.0
@export var speed: float = 60.0
@export var dmg: float = 8.0                   ## 触碰伤害
@export var radius: float = 30.0               ## 命中半径，技能判定用的就是它
@export var score: int = 10
@export var coin: int = 1
@export var tv: float = 8.0                    ## 击杀回复的时间之力

# ── 外观 ────────────────────────────────────────────────────────────
@export_group("外观")
@export_file("*.png") var tex: String = ""     ## 单张贴图。留空则用 anim_dir 或程序化绘制
@export_dir var anim_dir: String = ""          ## 帧动画根目录，下属子目录 = 状态(idle/move/hit/death…)
@export var tex_target: float = 84.0           ## 贴图缩放到的目标边长（像素）
@export var color: Color = Color("#1A1714")    ## 无贴图时程序化墨团的颜色
@export var use_pivot: bool = false            ## 勾上才启用 pivot_frac（脚底锚点类美术包）
@export var pivot_frac: Vector2 = Vector2(0.5, 0.875)
@export var draw_style: String = "blob"        ## 程序化绘制造型：blob / fast / tank / bomber
@export var inertia: bool = false              ## 移动是否带惯性过弯（疾影类手感）
## 动画状态名映射：美术包的攻击/蓄力目录名各不相同（如 attack_shard_barrage），在这里指过去。
## 留空则回落到 idle。
@export var anim_attack: String = "attack"
@export var anim_charge: String = ""

# ── 精英变体 ────────────────────────────────────────────────────────
@export_group("精英")
@export var is_elite: bool = false
@export var elite_of: String = ""              ## 继承自哪只小怪的 id（仅作溯源标注）
@export var scale_mul: float = 1.0             ## 形象放大倍率，同时放大 tex_target 与 radius
@export var tint: Color = Color(1, 1, 1, 1)    ## 改色：叠乘到 sprite.modulate

# ── 远程（behavior = RANGED）────────────────────────────────────────
@export_group("远程")
@export var attack_range: float = 420.0        ## 进入该距离停步开火
@export var attack_cd: float = 1.6             ## 开火间隔（秒）
@export var attack_windup: float = 0.35        ## 抬手时间，播 attack 动画
@export var bullet_speed: float = 260.0
@export var bullet_dmg: float = 6.0
@export var bullet_radius: float = 10.0        ## 子弹自身半径，命中与被销毁都用它
@export var bullet_life: float = 4.0
@export var bullet_color: Color = Color("#3D5A80")

# ── 冲锋（behavior = CHARGER）───────────────────────────────────────
@export_group("冲锋")
@export var charge_range: float = 600.0        ## 进入该距离开始蓄力
@export var charge_dist: float = 900.0         ## 冲锋总距离
@export var charge_time: float = 2.0           ## 蓄力时长
@export var charge_speed: float = 900.0        ## 冲锋速度
@export var charge_cd: float = 2.5             ## 冲完的收招/再蓄力间隔
@export var charge_warn_color: Color = Color("#C0392B")

# ── 分裂（behavior = SPLITTER）──────────────────────────────────────
@export_group("分裂")
@export var split_count: int = 3               ## 死亡时分裂数量
@export var split_child_id: String = ""        ## 子体配置 id，留空则不分裂
@export var split_spread: float = 46.0         ## 子体散开半径
## 子体出生无敌时长（秒）。父体死亡会在原地留下爆裂连锁，没有这段无敌，
## 子体一生出来就会被自家爆炸和范围技能一并清掉。
@export var split_child_invuln: float = 0.5

# ── 兼容层 ──────────────────────────────────────────────────────────
@export_group("兼容")
## 旧 cfg.type 字符串。main.gd 的掉落与爆裂连锁仍读它（tank 掉沙 / bomber 连锁）。
@export var legacy_type: String = "blob"

## 生成 main.gd 与 enemy.gd 沿用的 cfg 字典视图。
## 红线：这里的键名一个都不能少，技能命中判定全靠 cfg.radius / cfg.dmg。
func to_cfg() -> Dictionary:
	var c := {
		"id": id,
		"type": legacy_type,
		"behavior": behavior,
		"hp": hp,
		"speed": speed,
		"dmg": dmg,
		"radius": radius * scale_mul,
		"score": score,
		"coin": coin,
		"tv": tv,
		"tex": tex,
		"tex_target": tex_target * scale_mul,
		"color": color,
		"draw_style": draw_style,
		"inertia": inertia,
		"anim_attack": anim_attack,
		"anim_charge": anim_charge,
		"tint": tint,
		"is_elite": is_elite,
	}
	if anim_dir != "":
		c["anim_dir"] = anim_dir
	if use_pivot:
		c["pivot_frac"] = pivot_frac
	match behavior:
		Behavior.RANGED:
			_fill_ranged(c)
		Behavior.CHARGER:
			_fill_charger(c)
		Behavior.SPLITTER:
			c["split_count"] = split_count
			c["split_child_id"] = split_child_id
			c["split_spread"] = split_spread
			c["split_child_invuln"] = split_child_invuln
		Behavior.BOSS:
			# BOSS 复用小怪技能的组合，两套参数都带上
			_fill_ranged(c)
			_fill_charger(c)
	return c

func _fill_ranged(c: Dictionary) -> void:
	c["attack_range"] = attack_range
	c["attack_cd"] = attack_cd
	c["attack_windup"] = attack_windup
	c["bullet_speed"] = bullet_speed
	c["bullet_dmg"] = bullet_dmg
	c["bullet_radius"] = bullet_radius
	c["bullet_life"] = bullet_life
	c["bullet_color"] = bullet_color

func _fill_charger(c: Dictionary) -> void:
	c["charge_range"] = charge_range
	c["charge_dist"] = charge_dist
	c["charge_time"] = charge_time
	c["charge_speed"] = charge_speed
	c["charge_cd"] = charge_cd
	c["charge_warn_color"] = charge_warn_color
