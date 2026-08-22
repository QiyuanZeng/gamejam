class_name EnemyDB
extends RefCounted
## 怪物配置总入口。读 res://data/balance.tres 的 enemies 数组，按 EnemyData.id 建索引。
## 加一只新怪 = 在编辑器里打开 balance.tres，enemies 数组加一项，不用改任何代码。

static var _cache: Dictionary = {}     # id -> EnemyData
static var _loaded := false

static func all() -> Dictionary:
	if not _loaded:
		_load()
	return _cache

static func ids() -> Array:
	var ks := all().keys()
	ks.sort()
	return ks

static func has(id: String) -> bool:
	return all().has(id)

static func get_data(id: String) -> EnemyData:
	return all().get(id, null)

## 取该怪的 cfg 字典视图（已 duplicate，调用方可随意改）。
static func cfg(id: String) -> Dictionary:
	var d: EnemyData = get_data(id)
	if d == null:
		push_error("EnemyDB: 未找到怪物配置 id=%s" % id)
		return {}
	return d.to_cfg()

## 按行为筛选，供刷怪表与测试用。
static func by_behavior(b: int) -> Array:
	var out: Array = []
	for id in ids():
		var d: EnemyData = _cache[id]
		if d.behavior == b:
			out.append(d)
	return out

static func reload() -> void:
	_loaded = false
	_cache.clear()
	BalanceConfig.reload()
	_load()

static func _load() -> void:
	_loaded = true
	_cache.clear()
	for d in BalanceConfig.get_config().enemies:
		_add(d)
	if _cache.is_empty():
		push_error("EnemyDB: %s 的 enemies 是空的 —— 导出包请确认 data/ 已打进资源过滤器"
			% BalanceConfig.PATH)

static func _add(d: EnemyData) -> void:
	if d == null:
		push_warning("EnemyDB: enemies 里有空项，已跳过")
		return
	if d.id == "":
		push_error("EnemyDB: enemies 里有 id 为空的配置（%s）" % d.display_name)
		return
	if _cache.has(d.id):
		push_error("EnemyDB: id 重复 %s" % d.id)
		return
	_cache[d.id] = d
