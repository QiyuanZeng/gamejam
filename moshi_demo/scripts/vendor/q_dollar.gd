class_name QDollar
extends RefCounted
## $Q Super-Quick Recognizer —— 点云手势识别算法，移植自开源实现：
##   https://github.com/angrychill/q-dollar-gesture-godot  (MIT License, angrychill)
##   算法原论文：Vatavu, Anthony & Wobbrock, "$Q: A Super-Quick, Articulation-Invariant
##   Stroke-Gesture Recognizer for Low-Resource Devices" (MobileHCI 2018)
##
## 上游是可运行的示例工程而非库（作者自述 "Not fit for an add-on as it is currently"）：
## 识别器是靠扫描 res://gesture_templates 目录加载 .tres 的 Node，手势采集节点糅合了
## Line2D 绘制、磁盘存盘与自定义输入动作，classify() 只回手势名、不给分数也不会拒识。
## 这里只取纯算法部分并改成无状态静态函数，其余（Node / Resource / .tres / 绘制 / 存盘）
## 与本项目架构不兼容，一律不搬。
##
## 相对上游的两处刻意取舍：
##  1. 关闭下界剪枝（lower bounding）。它需要给每个手势建 64×64 的最近点查找表，
##     单次约 26 万次运算；本项目的候选笔画每帧都在变，建表开销远超剪枝收益。
##     且上游建表用 (row, col) 作键、查表却用 (col, row)，键被转置，剪枝结果不可信。
##  2. 保留 early abandoning（纯收益，不影响结果）。
##
## 点用 Vector3(x, y, stroke_index) 表示，z 为笔画序号 —— 这是 $Q 的原生数据模型，
## 重采样与弧长统计靠它避免跨笔画插值。本项目目前是单笔画，z 恒为 0。

const GREEDY_EPS := 0.5           # 贪心搜索起点密度（0~1，越小起点越多越准）

## 云距离 → 归一化的均方根偏差。归一化后形状跨度为 1，故 rms 可直接横比。
## 完全重合返回 0；越大越不像。
static func cloud_rms(a: Array[Vector3], b: Array[Vector3]) -> float:
	if a.is_empty() or a.size() != b.size():
		return INF
	var n := a.size()
	var d := greedy_cloud_match(a, b)
	if is_inf(d):
		return INF
	# cloud_distance 累加的是 weight × 平方距离，权重从 n 递减到 1，总权重 n(n+1)/2
	return sqrt(d / (float(n) * float(n + 1) * 0.5))

# ============================== $Q 核心（移植自上游） ==============================

static func greedy_cloud_match(points1: Array[Vector3], points2: Array[Vector3]) -> float:
	var n := points1.size()
	var step := int(floor(pow(float(n), 1.0 - GREEDY_EPS)))
	if step < 1:
		step = 1
	var min_so_far := INF
	for i in range(0, n, step):
		min_so_far = minf(min_so_far, cloud_distance(points1, points2, i, min_so_far))
		min_so_far = minf(min_so_far, cloud_distance(points2, points1, i, min_so_far))
	return min_so_far

static func cloud_distance(points1: Array[Vector3], points2: Array[Vector3],
		start_index: int, min_so_far: float) -> float:
	var n := points1.size()
	var not_matched: Array[int] = []
	not_matched.resize(n)
	for j in n:
		not_matched[j] = j
	var sum := 0.0
	var i := start_index
	var weight := n
	var head := 0
	while weight > 0:
		var index := -1
		var min_distance := INF
		for j in range(head, n):
			var dist := sq_euclidean_distance(points1[i], points2[not_matched[j]])
			if dist < min_distance:
				min_distance = dist
				index = j
		not_matched[index] = not_matched[head]
		sum += float(weight) * min_distance
		weight -= 1
		if sum >= min_so_far:      # early abandoning
			return sum
		i = (i + 1) % n
		head += 1
	return sum

# ============================== 归一化三件套（移植自上游） ==============================

static func resample(points: Array[Vector3], n: int) -> Array[Vector3]:
	var new_points: Array[Vector3] = []
	new_points.resize(n)
	new_points[0] = points[0]
	var num_points := 1
	var interval := path_length(points) / float(n - 1)
	if interval <= 0.0:
		for k in range(1, n):
			new_points[k] = points[0]
		return new_points
	var d := 0.0
	for i in range(1, points.size()):
		if points[i].z != points[i - 1].z:
			continue
		var small_d := euclidean_distance(points[i - 1], points[i])
		if d + small_d >= interval:
			var first := points[i - 1]
			while d + small_d >= interval and num_points < n:
				var t := clampf((interval - d) / small_d, 0.0, 1.0)
				if is_nan(t):
					t = 0.5
				new_points[num_points] = Vector3(
					(1.0 - t) * first.x + t * points[i].x,
					(1.0 - t) * first.y + t * points[i].y,
					points[i].z)
				num_points += 1
				small_d = d + small_d - interval
				d = 0.0
				first = new_points[num_points - 1]
			d = small_d
		else:
			d += small_d
	while num_points < n:
		new_points[num_points] = points[points.size() - 1]
		num_points += 1
	return new_points

## 等比缩放（按最长边），保长宽比，避免直线笔形被拉爆。
static func scale(points: Array[Vector3]) -> Array[Vector3]:
	var minx := INF
	var miny := INF
	var maxx := -INF
	var maxy := -INF
	for p in points:
		minx = minf(minx, p.x)
		miny = minf(miny, p.y)
		maxx = maxf(maxx, p.x)
		maxy = maxf(maxy, p.y)
	var k := maxf(maxx - minx, maxy - miny)
	if k <= 0.0:
		k = 1.0
	var out: Array[Vector3] = []
	out.resize(points.size())
	for i in points.size():
		out[i] = Vector3((points[i].x - minx) / k, (points[i].y - miny) / k, points[i].z)
	return out

static func translate(points: Array[Vector3], c: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	out.resize(points.size())
	for i in points.size():
		out[i] = Vector3(points[i].x - c.x, points[i].y - c.y, points[i].z)
	return out

static func centroid(points: Array[Vector3]) -> Vector3:
	var cx := 0.0
	var cy := 0.0
	for p in points:
		cx += p.x
		cy += p.y
	var n := float(points.size())
	return Vector3(cx / n, cy / n, 0.0)

## 弧长：跨笔画的间隔不计入。
static func path_length(points: Array[Vector3]) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		if points[i].z == points[i - 1].z:
			total += euclidean_distance(points[i - 1], points[i])
	return total

static func euclidean_distance(a: Vector3, b: Vector3) -> float:
	return sqrt(sq_euclidean_distance(a, b))

static func sq_euclidean_distance(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dy := a.y - b.y
	return dx * dx + dy * dy
