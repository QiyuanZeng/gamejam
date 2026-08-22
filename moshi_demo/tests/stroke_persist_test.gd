extends Node
## 自定义笔形持久化：跨进程验证「这次改的形，下次开局还在」。
##
## 单进程内 static 的 custom 字典会一直留着，测不出真读盘。所以分两趟跑：
##   第 1 趟（write）：改「时」的笔形并落盘，记下形状指纹。
##   第 2 趟（read） ：全新进程，只调 build_skills，断言拿到的是上一趟存的形。
## 趟次靠 user://stroke_persist_stage.txt 传递，跑完自动清理，不污染下次。

const STAGE_PATH := "user://stroke_persist_stage.txt"
const FIXED_ID := "time"

var fails: Array[String] = []

## 故意和出厂形差很远的一个形，避免「没生效」也能蒙混过关
static func mark_stroke() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, 0), Vector2(60, 12), Vector2(10, 30), Vector2(52, 48), Vector2(4, 60)])

func _ready() -> void:
	if _stage() == "read":
		_phase_read()
	else:
		_phase_write()

# ============================== 第 1 趟：写盘 ==============================

func _phase_write() -> void:
	print("— 第 1 趟：改笔形并落盘 —")
	SpellMatch.set_custom(FIXED_ID, PackedVector2Array())   # 先退回出厂，保证起点干净
	SpellMatch.save_custom()
	var factory := SpellMatch.ancient_stroke(FIXED_ID)
	_chk(not SpellMatch.is_custom(FIXED_ID), "起点是出厂形")

	SpellMatch.set_custom(FIXED_ID, mark_stroke())
	var err := SpellMatch.save_custom()
	_chk(err == OK, "落盘返回 OK（err=%d）" % err)
	_chk(FileAccess.file_exists(SpellMatch.CUSTOM_PATH),
		"生成文件 %s" % ProjectSettings.globalize_path(SpellMatch.CUSTOM_PATH))
	_chk(SpellMatch.is_custom(FIXED_ID), "内存里已标记为自定义")
	_chk(not _same(SpellMatch.ancient_stroke(FIXED_ID), factory), "生效的形已不是出厂形")

	# 立即重建技能表：改完不重开也该马上认新形
	var skills := SpellMatch.build_skills()
	var s := _find(skills, FIXED_ID)
	var sim := SpellMatch.similarity(SpellMatch.feature(_scaled(mark_stroke(), 4.0)), s)
	_chk(sim >= SpellMatch.SCORE_MIN, "当场重建技能表即认新形（%.0f%%）" % (sim * 100.0))

	_set_stage("read")
	_done("STROKE_PERSIST_WRITE")

# ============================== 第 2 趟：全新进程读盘 ==============================

func _phase_read() -> void:
	print("— 第 2 趟：全新进程，只读盘 —")
	# 这一趟没人调过 set_custom，custom 字典完全靠 load_custom 从磁盘填
	_chk(SpellMatch.custom.is_empty(), "进程起点内存是空的（还没读盘）")

	var skills := SpellMatch.build_skills()
	var s := _find(skills, FIXED_ID)
	_chk(not s.is_empty() and bool(s.bound), "技能「%s」出生即绑定" % FIXED_ID)
	_chk(SpellMatch.is_custom(FIXED_ID), "读盘后识别为自定义形")
	_chk(_same(SpellMatch.ancient_stroke(FIXED_ID), mark_stroke()), "读回来的点和存进去的一致")

	var hit := SpellMatch.similarity(SpellMatch.feature(_scaled(mark_stroke(), 4.0)), s)
	_chk(hit >= SpellMatch.SCORE_MIN, "画上一趟保存的形能命中（%.0f%%）" % (hit * 100.0))
	var miss := SpellMatch.similarity(
		SpellMatch.feature(_scaled(SpellMatch.default_stroke(FIXED_ID), 4.0)), s)
	_chk(miss < SpellMatch.SCORE_MIN, "画出厂形反而不命中（%.0f%%）—— 说明确实换了形" % (miss * 100.0))

	# 收尾：把自定义清掉并删掉阶段标记，别把测试残留带给下次运行
	SpellMatch.set_custom(FIXED_ID, PackedVector2Array())
	SpellMatch.save_custom()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STAGE_PATH))
	_done("STROKE_PERSIST")

# ============================== helper ==============================

func _stage() -> String:
	if not FileAccess.file_exists(STAGE_PATH):
		return "write"
	var f := FileAccess.open(STAGE_PATH, FileAccess.READ)
	if f == null:
		return "write"
	var s := f.get_as_text().strip_edges()
	f.close()
	return s

func _set_stage(v: String) -> void:
	var f := FileAccess.open(STAGE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(v)
		f.close()

func _find(skills: Array, id: String) -> Dictionary:
	for s in skills:
		if String(s.id) == id:
			return s
	return {}

func _same(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].distance_to(b[i]) > 0.05:
			return false
	return true

func _scaled(src: PackedVector2Array, k: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in src:
		pts.append(p * k)
	var out := PackedVector2Array([pts[0]])
	for i in range(1, pts.size()):
		var n: int = maxi(int(pts[i - 1].distance_to(pts[i]) / 6.0), 1)
		for j in range(1, n + 1):
			out.append(pts[i - 1].lerp(pts[i], float(j) / float(n)))
	return out

func _chk(cond: bool, msg: String) -> void:
	print(("ok   " if cond else "BAD  "), msg)
	if not cond:
		fails.append(msg)

func _done(tag: String) -> void:
	for f in fails:
		print("FAIL: ", f)
	print(tag, " ", "PASS" if fails.is_empty() else "FAIL")
	get_tree().quit(1 if not fails.is_empty() else 0)
