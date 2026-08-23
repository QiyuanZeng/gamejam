class_name SpellConfig
extends Resource
## 施法限制表。「一笔画出去，到底认不认、放不放」的全部门槛收在这一份
## res://data/spell.tres 里，编辑器双击打开，Inspector 里改完存盘即生效。
##
## 一次施法要过的闸，按判定顺序：
##   ① 起笔     —— 墨（时间之力）低于 bullet_exit_tv 起不了笔       → data/player.tres「笔墨」
##   ② 画线     —— 每 px 扣 tv_cost_per_px 的墨，墨干了自动收笔      → data/player.tres「笔墨」
##   ③ 长度闸   —— 笔画短于 min_len 不参与神纹判定，只出斩击          → 本表
##   ④ 形状闸   —— 与神纹笔形的相似度要 ≥ score_min 才算命中          → 本表
##   ⑤ 冷却闸   —— 该神纹 cd_left > 0 时跳过，不参与本次比对          → data/player.tres「神纹」
##   ⑥ 多命中   —— 都过闸时取得分最高的那道放出来                      → 无参数
## 没命中的长笔画还要再过觉醒的三道闸（烧墨比例 / 撞形 / 掷骰），见下方「觉醒绑形」组。
##
## 释放本身不额外收墨钱，也没有前摇后摇、施法距离、全局公共冷却 —— 目前没有这些限制。
## 神纹各自的冷却与效果数值在 res://data/player.tres（PlayerConfig）的「神纹」组。

const PATH := "res://data/spell.tres"

# ============================== 笔形识别 ==============================

@export_group("笔形识别")
## 笔画长度门槛（px）。短于它的笔画一律不进神纹判定，只当普通斩击。
## 调小 = 短笔也能放技能（误触变多），调大 = 必须画满一大笔。
@export var min_len: float = 120.0
## 命中门槛：画出来的形与神纹笔形的相似度要到这个值才放技能。
## 0.82 是实测的拒识上界（74%）与命中下界（90%）的中点。调小更好放但更容易放错道。
@export var score_min: float = 0.82
## 得分归一基准：$Q 的点云 rms 达到这个值即判 0 分。
## 它决定分数曲线的陡峭程度 —— 调大则整体分数虚高，一般不用动。
@export var rms_ref: float = 0.35

# ============================== 觉醒绑形 ==============================

@export_group("觉醒绑形")
## 与已激活神纹的相似度上界：新笔形跟老神纹像到这个程度，就算「撞形」，不给绑。
## 卡太严（如 0.5）会因为 $Q 的分数基线偏高而把觉醒永久关死。
@export var bind_max_sim: float = 0.70

## 觉醒的另外两道闸 —— 这一笔要烧掉起笔余额的多少比例（bind_energy_ratio）、
## 过闸后的触发概率（bind_chance）—— 在 res://data/player.tres 的「觉醒」组，不在本表重复。

static var _inst: SpellConfig = null

## 取全局唯一实例。加载不到就退回一份代码默认值，保证不崩。
static func get_config() -> SpellConfig:
	if _inst == null:
		var res := ResourceLoader.load(PATH)
		if res is SpellConfig:
			_inst = res
		else:
			push_error("SpellConfig: 加载不到 %s —— 导出包请确认 data/ 已打进资源过滤器" % PATH)
			_inst = SpellConfig.new()
	return _inst

## 重新从磁盘读一遍。
static func reload() -> SpellConfig:
	_inst = null
	var res := ResourceLoader.load(PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if res is SpellConfig:
		_inst = res
	return get_config()
