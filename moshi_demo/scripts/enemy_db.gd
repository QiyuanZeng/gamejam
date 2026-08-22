class_name EnemyDB
extends RefCounted
## 怪物配置总入口。扫描 res://data/enemies/ 下全部 .tres，按 EnemyData.id 建索引。
## 加一只新怪 = 在该目录丢一个 .tres，不用改任何代码。

const DIR := "res://data/enemies/"

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
	_load()

static func _load() -> void:
	_loaded = true
	_cache.clear()
	var dir := DirAccess.open(DIR)
	if dir == null:
		push_error("EnemyDB: 打不开目录 %s" % DIR)
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir():
			# 导出包里资源可能带 .remap 后缀，剥掉再 load
			var name := f
			if name.ends_with(".remap"):
				name = name.trim_suffix(".remap")
			if name.get_extension().to_lower() == "tres":
				_add(DIR.path_join(name))
		f = dir.get_next()
	dir.list_dir_end()
	if _cache.is_empty():
		push_error("EnemyDB: %s 下没扫到任何 .tres —— 导出包请确认 data/ 已打进资源过滤器" % DIR)

static func _add(path: String) -> void:
	var res := ResourceLoader.load(path)
	if res == null or not (res is EnemyData):
		push_warning("EnemyDB: 跳过非 EnemyData 资源 %s" % path)
		return
	var d: EnemyData = res
	if d.id == "":
		push_error("EnemyDB: %s 的 id 为空" % path)
		return
	if _cache.has(d.id):
		push_error("EnemyDB: id 重复 %s（%s）" % [d.id, path])
		return
	_cache[d.id] = d
