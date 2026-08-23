extends Node
## $Q 点云识别专项：不变性（平移/缩放/倾斜/手抖/反向书写）与拒识（乱涂/直线/异形字）双向标定。
## 反向书写是 $Q 相对 $1 的关键增益：点云无序，从哪头起笔都该命中。

var fails: Array[String] = []
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 20260822
	SpellMatch.load_config()          # 门槛按 data/spell.tres 走，别用代码兜底值
	var skills := SpellMatch.build_skills()
	# 不写死下标：神纹录顺序调过一次了，改用 id 查，省得下回再全篇返工
	var lei := _find(skills, "thunder")
	var mu := _find(skills, "ent")
	var base := SpellMatch.ancient_stroke("thunder")

	print("— 不变性（应命中，门槛 %.0f%%）—" % (SpellMatch.SCORE_MIN * 100.0))
	_expect(true, lei, _xform(base, 3.0, 0.0, Vector2.ZERO), "原形 ×3")
	_expect(true, lei, _xform(base, 3.0, 0.0, Vector2(500, 300)), "平移 +500,300")
	_expect(true, lei, _xform(base, 1.6, 0.0, Vector2.ZERO), "缩小 ×1.6")
	_expect(true, lei, _xform(base, 6.0, 0.0, Vector2.ZERO), "放大 ×6")
	_expect(true, lei, _reverse(_xform(base, 3.0, 0.0, Vector2.ZERO)), "反向书写（末端起笔）")
	_expect(true, lei, _xform(base, 3.0, deg_to_rad(10.0), Vector2.ZERO), "倾斜 10°")
	_expect(true, lei, _xform(base, 3.0, deg_to_rad(-15.0), Vector2.ZERO), "倾斜 -15°")
	_expect(true, lei, _jitter(_xform(base, 3.0, 0.0, Vector2.ZERO), 6.0), "手抖 ±6px")
	_expect(true, lei, _reverse(_jitter(_xform(base, 3.0, 0.0, Vector2.ZERO), 6.0)),
		"反向 + 手抖 ±6px")

	print("— 拒识（不应命中）—")
	_expect(false, lei, _xform(SpellMatch.ancient_stroke("ent"), 3.0, 0.0, Vector2.ZERO),
		"「木」错认成「雷」")
	_expect(false, mu, _xform(base, 3.0, 0.0, Vector2.ZERO), "「雷」错认成「木」")
	_expect(false, lei, _circle(Vector2(400, 300), 120.0), "乱涂圆圈")
	_expect(false, lei, _line(Vector2(100, 300), Vector2(560, 300)), "一条直线")

	print("— 门槛（笔太短）—")
	_expect(false, lei, _xform(base, 0.4, 0.0, Vector2.ZERO), "笔长不足 120px")

	print("— 分辨力 —")
	var s_self := _score(lei, _xform(base, 3.0, 0.0, Vector2.ZERO))
	var s_mu := _score(lei, _xform(SpellMatch.ancient_stroke("ent"), 3.0, 0.0, Vector2.ZERO))
	_chk(s_self - s_mu > 0.2,
		"自匹配 %.0f%% 与异形 %.0f%% 拉开 %.0f 个百分点" % [
			s_self * 100.0, s_mu * 100.0, (s_self - s_mu) * 100.0])

	print("— 多候选取最高分 —")
	var probe2 := SpellMatch.feature(_xform(base, 3.0, 0.0, Vector2.ZERO))
	var pick := SpellMatch.best_match(probe2, skills)
	_chk(int(pick.i) >= 0 and String(skills[int(pick.i)].id) == "thunder",
		"「雷」形在全表里挑中「雷霆万钧」（%.0f%%）" % (float(pick.sim) * 100.0))
	_chk(float(pick.top) >= SpellMatch.SCORE_MIN, "top 带出全表最高分 %.0f%%" % (float(pick.top) * 100.0))
	lei.cd_left = 3.0
	_chk(int(SpellMatch.best_match(probe2, skills).i) < 0, "冷却中的神纹不参与释放")
	lei.cd_left = 0.0

	print("— 性能 —")
	var probe := SpellMatch.feature(_xform(base, 3.0, 0.0, Vector2.ZERO))
	var t0 := Time.get_ticks_usec()
	for i in 20:
		for s in skills:
			SpellMatch.similarity(probe, s)
	var us := float(Time.get_ticks_usec() - t0) / 20.0
	_chk(us < 40000.0, "单笔比对 5 神纹耗时 %.1f ms" % (us / 1000.0))

	for f in fails:
		print("FAIL: ", f)
	print("QDOLLAR ", "PASS" if fails.is_empty() else "FAIL")
	get_tree().quit(1 if not fails.is_empty() else 0)

func _find(skills: Array, id: String) -> Dictionary:
	for s in skills:
		if String(s.id) == id:
			return s
	return {}

func _score(skill: Dictionary, path: PackedVector2Array) -> float:
	return SpellMatch.similarity(SpellMatch.feature(path), skill)

func _expect(want: bool, skill: Dictionary, path: PackedVector2Array, label: String) -> void:
	var chk := SpellMatch.check(SpellMatch.feature(path), skill)
	_chk(bool(chk.ok) == want, "%-22s 得分 %5.1f%%  %s" % [
		label, float(chk.sim) * 100.0, String(chk.reason)])

## 缩放 + 绕原点旋转 + 平移，并按 6px 采样补点，模拟真实书写密度。
func _xform(src: PackedVector2Array, k: float, ang: float, off: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in src:
		pts.append((p * k).rotated(ang) + off)
	return _densify(pts)

func _reverse(src: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(src.size() - 1, -1, -1):
		out.append(src[i])
	return out

func _jitter(src: PackedVector2Array, amp: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in src:
		out.append(p + Vector2(rng.randf_range(-amp, amp), rng.randf_range(-amp, amp)))
	return out

func _circle(c: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 49:
		var a := TAU * float(i) / 48.0
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out

func _line(a: Vector2, b: Vector2) -> PackedVector2Array:
	return _densify(PackedVector2Array([a, b]))

func _densify(ctrl: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if ctrl.is_empty():
		return out
	out.append(ctrl[0])
	for i in range(1, ctrl.size()):
		var a: Vector2 = ctrl[i - 1]
		var b: Vector2 = ctrl[i]
		var n: int = maxi(int(a.distance_to(b) / 6.0), 1)
		for k in range(1, n + 1):
			out.append(a.lerp(b, float(k) / float(n)))
	return out

func _chk(cond: bool, msg: String) -> void:
	print(("ok   " if cond else "BAD  "), msg)
	if not cond:
		fails.append(msg)
