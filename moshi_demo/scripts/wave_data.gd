class_name WaveData
extends Resource
## 刷怪波段配置。全部波段收在 res://data/balance.tres 的 waves 数组里，
## 编辑器双击那份总表，展开对应的一项就能改刷怪频率与配比。
## 段与段按 until_time 从小到大排队；until_time 最大的那一段兼作**永久平台期**
## （本局没有时限，跑过最后一段的时间点后就一直用它）。详见 docs/enemies.md。

@export var id: String = ""                 ## 段名，仅用于调试与文档对照
@export var until_time: float = 5.0         ## run_time 小于它就走这一段（秒）
@export var interval: float = 0.5           ## 每隔多少秒刷一只（这就是刷怪频率）
@export var cap: int = 18                   ## 本段场上怪物数上限（还受总表 max_enemies 硬顶约束）
@export var mix: Dictionary = {}            ## EnemyData.id -> 权重，权重和应为 1.0
@export_multiline var note: String = ""     ## 这一段想营造什么节奏，写给人看的

## 按权重掷一只怪的 id。权重和不为 1 时按实际总和归一，配歪了也不会刷不出怪。
func roll(rng_value: float) -> String:
	if mix.is_empty():
		return ""
	var total := 0.0
	for k in mix:
		total += float(mix[k])
	if total <= 0.0:
		return String(mix.keys()[0])
	var roll_at := rng_value * total
	var acc := 0.0
	for k in mix:
		acc += float(mix[k])
		if roll_at <= acc:
			return String(k)
	return String(mix.keys()[mix.size() - 1])

## 权重和，用于配表体检
func weight_sum() -> float:
	var total := 0.0
	for k in mix:
		total += float(mix[k])
	return total
