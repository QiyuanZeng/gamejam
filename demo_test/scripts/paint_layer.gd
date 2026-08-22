class_name PaintLayer
extends Node2D
## 通用绘制层：外部注入 paint 回调（接收本层节点），由主控每帧 queue_redraw。

var paint: Callable

func _draw() -> void:
	if paint.is_valid():
		paint.call(self)
