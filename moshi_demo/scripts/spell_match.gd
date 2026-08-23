class_name SpellMatch
extends RefCounted
## 咒语笔形识别 —— 基于 $Q Point-Cloud Recognizer，纯函数库、无状态、不依赖 Game。
## 算法实现见 scripts/vendor/q_dollar.gd（移植自 angrychill/q-dollar-gesture-godot，MIT）。
## 主玩法（Game）与调试台（SpellLab）共用这一份阈值与判定，杜绝两边逻辑漂移。
##
## $Q 把笔画视作点云做双向贪心最近点匹配，因此天然对「从哪头起笔、顺时逆时、多笔先后」
## 免疫 —— 只认最终落在纸上的形状。代价是丢弃行笔时序，轨迹重合而走法不同的笔形无法区分。

const SAMPLES := 32                     # 重采样点数（比对开销随 n² 增长，32 足够且够快）

## —— 施法门槛。默认值只是兜底，开局由 load_config() 从 res://data/spell.tres 覆盖 ——
## 想调「多长的笔才算数」「画得多像才认」，去改那份表，别改这里。
static var MIN_LEN := 120.0             # 笔画长度门槛（px）
static var SCORE_MIN := 0.82            # 匹配得分门槛（拒识上界 74% 与命中下界 90% 的中点）
static var RMS_REF := 0.35              # 得分归一基准：rms 达到此值即判 0 分
## 与已激活神纹的相似度上界：超过就算「跟别人撞了」，不给绑。
## 策划案原文写 50%，但 $Q 的分数基线本来就高 —— 实测圆/三角/螺旋/星形这些跟出厂形
## 八竿子打不着的形，也能拿 50~70%，按 50% 卡等于把觉醒永久关死（见 tests/shape_diag 实测）。
## 取 70%：明显低于 82% 的命中门槛（留 12 点余量，不至于误判成命中），又真能放行陌生形。
static var BIND_MAX_SIM := 0.70

## 把施法门槛表灌进来。main / spell_lab 的 _ready 各调一次，两边共用同一份数。
static func load_config() -> void:
	apply_config(SpellConfig.get_config())

static func apply_config(cfg: SpellConfig) -> void:
	if cfg == null:
		return
	MIN_LEN = cfg.min_len
	SCORE_MIN = cfg.score_min
	RMS_REF = cfg.rms_ref
	BIND_MAX_SIM = cfg.bind_max_sim


## 神纹录。**古代神纹必须排在最前** —— HUD 的可绑槽列表、调试台的试录键位都锚定
## 「可绑槽从古代神纹之后起」。调顺序要一起改。
##   古代神纹（ancient）：项目预设，出生即激活，笔形可在 F2 台精修但抹不掉。
##   普通神纹（normal） ：空碑，战斗中由玩家的长笔画随机激活并绑形，可在神纹录抹除重绑。
const SKILL_DEFS := [
	{"id": "thunder", "name": "雷霆万钧", "ancient": true, "cd": 6.0},
	{"id": "ent", "name": "妖木精灵", "ancient": true, "cd": 20.0},
	{"id": "quake", "name": "山崩地裂", "ancient": false, "cd": 12.0},
	{"id": "flood", "name": "水漫金山", "ancient": false, "cd": 10.0},
	{"id": "swords", "name": "无限剑阵", "ancient": false, "cd": 14.0},
]

## 古代神纹 id，按表内顺序。调试台的 1/2 键、恢复默认都据此取，不写死。
static func ancient_ids() -> Array:
	var out: Array = []
	for def in SKILL_DEFS:
		if bool(def.ancient):
			out.append(String(def.id))
	return out

static func is_ancient(id: String) -> bool:
	return id in ancient_ids()

## 玩家在 F2 调试台改过的古代神纹笔形，键为技能 id。空表示用出厂形。
static var custom: Dictionary = {}
static var _custom_loaded := false

const CUSTOM_PATH := "user://spell_strokes.json"

## 出厂笔形（单笔近似）：「雷」取闪电折返，「木」取一横一竖加撇捺。
## $Q 只认最终落纸的形状、不认笔序，所以多笔的字要按「一笔连写」写死 —— 回描的那几段
## 只是让点云在主干上更密，不影响判定。
## 两个形状刻意拉开差异 —— 一个是三折闪电、一个是十字带撇捺，最长弦转正后仍不会互认。
## 「木」的捺特意拖得比撇长：最长弦（横左端 → 捺末端）由此唯一，转正角才稳；
## 左右对称的写法会出现两条等长弦，采样稍有出入就把整个形甩转 40°，直接把匹配打废。
static func default_stroke(id: String) -> PackedVector2Array:
	match id:
		"thunder":
			return PackedVector2Array([
				Vector2(36, 0), Vector2(4, 34), Vector2(30, 34), Vector2(0, 72)])
		"ent":
			return PackedVector2Array([
				Vector2(2, 20), Vector2(62, 20),          # 横
				Vector2(32, 20), Vector2(32, 80),          # 回描到中点，往下写竖
				Vector2(32, 44), Vector2(4, 72),           # 回描到交叉点，撇
				Vector2(32, 44), Vector2(72, 88)])         # 再回交叉点，捺
	return PackedVector2Array()

## 当前生效的古代神纹笔形：玩家改过就用改过的，否则回落出厂形。
static func ancient_stroke(id: String) -> PackedVector2Array:
	load_custom()
	if custom.has(id):
		return (custom[id] as PackedVector2Array).duplicate()
	return default_stroke(id)

static func is_custom(id: String) -> bool:
	load_custom()
	return custom.has(id)

## 改笔形。传空表示恢复出厂。只落内存，写盘要另外调 save_custom()。
static func set_custom(id: String, pts: PackedVector2Array) -> void:
	load_custom()
	if pts.size() < 2:
		custom.erase(id)
	else:
		custom[id] = pts.duplicate()

static func load_custom() -> void:
	if _custom_loaded:
		return
	_custom_loaded = true
	if not FileAccess.file_exists(CUSTOM_PATH):
		return
	var f := FileAccess.open(CUSTOM_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary):
		return
	for id in data:
		var raw = data[id]
		if not (raw is Array) or raw.size() < 4 or raw.size() % 2 != 0:
			continue
		var pts := PackedVector2Array()
		for i in range(0, raw.size(), 2):
			pts.append(Vector2(float(raw[i]), float(raw[i + 1])))
		custom[String(id)] = pts

static func save_custom() -> Error:
	# 存成扁平数组（x,y,x,y…）：JSON 没有向量类型，来回转 Dictionary 更啰嗦也更易错
	var data := {}
	for id in custom:
		var flat: Array = []
		for p in (custom[id] as PackedVector2Array):
			flat.append(snappedf(p.x, 0.01))
			flat.append(snappedf(p.y, 0.01))
		data[id] = flat
	var f := FileAccess.open(CUSTOM_PATH, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return OK

## 生成一局的神纹录：古代神纹出生即激活，普通神纹留空待玩家的长笔画点亮。
static func build_skills() -> Array:
	var out: Array = []
	for def in SKILL_DEFS:
		var s := {
			"id": def.id, "name": def.name, "ancient": bool(def.ancient),
			"cd": float(def.cd), "cd_left": 0.0,
			"cloud": [] as Array[Vector3], "bound": false,
		}
		if bool(def.ancient):
			var feat := feature(ancient_stroke(String(def.id)))
			s.cloud = feat.cloud
			s.bound = true
		out.append(s)
	return out

## 沿折线按弧长取点，t ∈ [0,1]。回溯与分身重放在用，不参与识别。
static func point_along(path: PackedVector2Array, t: float) -> Vector2:
	if path.is_empty():
		return Vector2.ZERO
	if path.size() == 1:
		return path[0]
	var total := arc_len(path)
	if total <= 0.0:
		return path[0]
	var target := total * t
	var acc := 0.0
	for i in path.size() - 1:
		var seg := path[i].distance_to(path[i + 1])
		if seg <= 0.0:
			continue
		if acc + seg >= target:
			return path[i].lerp(path[i + 1], (target - acc) / seg)
		acc += seg
	return path[path.size() - 1]

static func arc_len(path: PackedVector2Array) -> float:
	var total := 0.0
	for i in path.size() - 1:
		total += path[i].distance_to(path[i + 1])
	return total

## 笔形特征：{cloud: 归一化点云, cloud_flip: 转正后再转 180° 的同一点云, px: 原始笔画总长}。
## $Q 本身不含旋转不变性，这里在重采样后按「最长弦」方向转正，再交给 $Q 的缩放与质心归一。
## 弦方向只到 π，剩下的 180° 二义靠候选侧多留一份翻转版解决，比对时取更优者。
static func feature(path: PackedVector2Array) -> Dictionary:
	if path.size() < 2:
		return {}
	var total := arc_len(path)
	if total < 1.0:
		return {}
	var pts: Array[Vector3] = []
	pts.resize(path.size())
	for i in path.size():
		pts[i] = Vector3(path[i].x, path[i].y, 0.0)   # 单笔画，笔序恒为 0
	var res := QDollar.resample(pts, SAMPLES)
	if res.is_empty():
		return {}
	var ang := _chord_angle(res)
	return {
		"cloud": _finish(res, -ang),
		"cloud_flip": _finish(res, -ang + PI),
		"px": total,
	}

static func _finish(res: Array[Vector3], ang: float) -> Array[Vector3]:
	var scaled := QDollar.scale(_rotate(res, ang))
	return QDollar.translate(scaled, QDollar.centroid(scaled))

static func _rotate(points: Array[Vector3], ang: float) -> Array[Vector3]:
	var cs := cos(ang)
	var sn := sin(ang)
	var out: Array[Vector3] = []
	out.resize(points.size())
	for i in points.size():
		var p := points[i]
		out[i] = Vector3(p.x * cs - p.y * sn, p.x * sn + p.y * cs, p.z)
	return out

## 转正基准：点云内最长的一条弦的方向（值域 [0, π)）。
## 不用二阶矩主轴 —— 汉字笔形的横竖跨度往往接近（实测特征比 0.85），主轴几乎不可辨，
## 采样点稍有增减就能让它甩出 20°，直接把匹配打废。最长弦由两个极端点定死，稳得多。
static func _chord_angle(points: Array[Vector3]) -> float:
	var best := -1.0
	var out := 0.0
	var n := points.size()
	for i in n:
		var a := points[i]
		for j in range(i + 1, n):
			var dx := points[j].x - a.x
			var dy := points[j].y - a.y
			var d2 := dx * dx + dy * dy
			if d2 > best:
				best = d2
				out = atan2(dy, dx)
	return out

## 匹配得分 ∈ [0,1]，1 为完全重合；无法比较返回 -2.0。
static func similarity(feat: Dictionary, skill: Dictionary) -> float:
	if feat.is_empty() or not bool(skill.get("bound", false)):
		return -2.0
	var b: Array[Vector3] = skill.get("cloud", [] as Array[Vector3])
	if b.is_empty():
		return -2.0
	var best := INF
	for key in ["cloud", "cloud_flip"]:
		var a: Array[Vector3] = feat.get(key, [] as Array[Vector3])
		if a.size() != b.size():
			continue
		best = minf(best, QDollar.cloud_rms(a, b))
	if is_inf(best):
		return -2.0
	return clampf(1.0 - best / RMS_REF, 0.0, 1.0)

## 完整判定明细：{ok, sim, len_ok, sim_ok, reason}
static func check(feat: Dictionary, skill: Dictionary) -> Dictionary:
	var out := {"ok": false, "sim": -2.0, "len_ok": false, "sim_ok": false, "reason": ""}
	if not bool(skill.get("bound", false)):
		out.reason = "未绑定"
		return out
	if feat.is_empty():
		out.reason = "笔画无效"
		return out
	var px := float(feat.get("px", 0.0))
	out.len_ok = px >= MIN_LEN
	var sim := similarity(feat, skill)
	out.sim = sim
	out.sim_ok = sim >= SCORE_MIN
	out.ok = out.len_ok and out.sim_ok
	if out.ok:
		out.reason = "命中"
	elif not out.len_ok:
		out.reason = "笔太短 %.0f < %.0f" % [px, MIN_LEN]
	else:
		out.reason = "形状 %.0f%% < %.0f%%" % [sim * 100.0, SCORE_MIN * 100.0]
	return out

static func matches(feat: Dictionary, skill: Dictionary) -> bool:
	return bool(check(feat, skill).ok)

## 在神纹录里挑一个来释放：多个都过门槛时取得分最高的那个（策划案原文）。
## 返回 {i: 命中下标，没有则 -1；sim: 命中者得分；top: 全表最高分，含冷却中与未过门槛的}。
## top 供绑定判定复用 —— 一次 O(n²) 比对同时喂给「释放」和「这形是不是撞了别人」两处。
static func best_match(feat: Dictionary, skills: Array) -> Dictionary:
	var out := {"i": -1, "sim": 0.0, "top": 0.0}
	if feat.is_empty():
		return out
	var long_enough := float(feat.get("px", 0.0)) >= MIN_LEN
	var best := SCORE_MIN
	for i in skills.size():
		var s: Dictionary = skills[i]
		var sim := similarity(feat, s)
		if sim <= -2.0:
			continue
		out.top = maxf(float(out.top), sim)
		if not long_enough or float(s.cd_left) > 0.0 or sim < best:
			continue
		best = sim
		out.i = i
		out.sim = sim
	return out
