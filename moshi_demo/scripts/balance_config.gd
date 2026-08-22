class_name BalanceConfig
extends Resource
## 配平总表。怪物数值、刷怪波表、刷怪全局参数全部收在这一份
## res://data/balance.tres 里，编辑器双击打开，Inspector 里改完存盘即生效。
##
## 结构：
##   刷怪全局 → max_enemies / spawn_margin
##   怪物     → enemies，一项一只怪（EnemyData，展开就能改血量/伤害/速度…）
##   波表     → waves，一项一段（WaveData，改 interval 就是改刷怪频率）
##
## 新增一只怪：enemies 数组加一项 → 选 New EnemyData → 填 id 与数值。
## 新增一段波次：waves 数组加一项 → 选 New WaveData → 填 until_time / interval / mix。
## 详见 docs/enemies.md。

const PATH := "res://data/balance.tres"

@export_group("刷怪全局")
## 全场怪物数硬顶。波表每段的 cap 再高也不会越过它。
@export var max_enemies: int = 130
## 刷怪点距竞技场边界的内缩距离（像素）。
@export var spawn_margin: float = 26.0

@export_group("怪物")
## 全部怪物配置。id 必须唯一，刷怪表与分裂都按 id 引用。
@export var enemies: Array[EnemyData] = []

@export_group("波表")
## 全部刷怪波段。段序按 until_time 自动排，不看数组顺序。
@export var waves: Array[WaveData] = []

static var _inst: BalanceConfig = null

## 取全局唯一实例。加载不到就退回一份代码默认值，保证不崩。
static func get_config() -> BalanceConfig:
	if _inst == null:
		var res := ResourceLoader.load(PATH)
		if res is BalanceConfig:
			_inst = res
		else:
			push_error("BalanceConfig: 加载不到 %s —— 导出包请确认 data/ 已打进资源过滤器" % PATH)
			_inst = BalanceConfig.new()
	return _inst

## 重新从磁盘读一遍，顺带让 EnemyDB / WaveDB 的索引失效。
static func reload() -> BalanceConfig:
	_inst = null
	var res := ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if res is BalanceConfig:
		_inst = res
	return get_config()
