class_name WaveDB
extends RefCounted
## 刷怪波表总入口。读 res://data/balance.tres 的 waves 数组，按 until_time 排好队。
## 加一段新波次 = 在编辑器里打开 balance.tres，waves 数组加一项，不用改任何代码。

static var _segs: Array = []       # 按 until_time 升序
static var _loaded := false

static func all() -> Array:
	if not _loaded:
		_load()
	return _segs

## 取当前时刻该用哪一段。跑过最后一段的时间点后一直返回最后一段（永久平台期）。
static func seg_for(run_time: float) -> WaveData:
	var segs := all()
	if segs.is_empty():
		return null
	for w in segs:
		if run_time < w.until_time:
			return w
	return segs[segs.size() - 1]

## 永久平台期那一段
static func final_seg() -> WaveData:
	var segs := all()
	return null if segs.is_empty() else segs[segs.size() - 1]

static func reload() -> void:
	_loaded = false
	_segs.clear()
	BalanceConfig.reload()
	_load()

## 配表体检：返回问题清单，空数组代表没毛病。测试与开发期自检用。
static func validate() -> Array:
	var errs: Array = []
	var segs := all()
	if segs.is_empty():
		errs.append("波表为空：%s 的 waves 一段都没有" % BalanceConfig.PATH)
		return errs
	for w in segs:
		if w.interval <= 0.0:
			errs.append("%s 的 interval 必须大于 0" % w.id)
		if w.cap <= 0:
			errs.append("%s 的 cap 必须大于 0" % w.id)
		if w.mix.is_empty():
			errs.append("%s 的 mix 是空的，刷不出怪" % w.id)
		for k in w.mix:
			if not EnemyDB.has(String(k)):
				errs.append("%s 的 mix 引用了不存在的怪 id：%s" % [w.id, String(k)])
			if float(w.mix[k]) <= 0.0:
				errs.append("%s 里 %s 的权重不是正数" % [w.id, String(k)])
		if absf(w.weight_sum() - 1.0) > 0.001:
			errs.append("%s 的权重和是 %.3f，不是 1.0" % [w.id, w.weight_sum()])
	return errs

static func _load() -> void:
	_loaded = true
	_segs.clear()
	for w in BalanceConfig.get_config().waves:
		if w == null:
			push_warning("WaveDB: waves 里有空项，已跳过")
			continue
		_segs.append(w)
	if _segs.is_empty():
		push_error("WaveDB: %s 的 waves 是空的 —— 导出包请确认 data/ 已打进资源过滤器"
			% BalanceConfig.PATH)
		return
	_segs.sort_custom(func(a, b): return a.until_time < b.until_time)
