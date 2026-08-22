extends Node
## InkStyle（autoload）—— 全局水墨样式提供器。
## 加载顺序：user://ink_style.tres（玩家保存）→ res://ink_style.tres（默认预设）→ 代码默认。
##
## 运行时实时修改接口（任意处调用即生效，渲染器每帧读取）：
##   InkStyle.set_param(&"feibai_chance", 0.8)
##   InkStyle.set_param(&"ink_color", Color.BLACK)
##   InkStyle.apply_style(other_style)
##   InkStyle.save_user() / InkStyle.reset_default()
##   监听 signal style_changed 可联动 UI。

signal style_changed

const USER_PATH := "user://ink_style.tres"
const RES_PATH := "res://ink_style.tres"

var current: InkBrushStyle

func _ready() -> void:
	current = _load_active()

func _load_active() -> InkBrushStyle:
	if FileAccess.file_exists(USER_PATH):
		var s := ResourceLoader.load(USER_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
		if s is InkBrushStyle:
			return s
	if ResourceLoader.exists(RES_PATH):
		var s := ResourceLoader.load(RES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
		if s is InkBrushStyle:
			return s
	return InkBrushStyle.new()

func set_param(prop: StringName, value: Variant) -> void:
	if current == null:
		current = InkBrushStyle.new()
	# 脱离已保存资源实例，避免把改动写回磁盘上的共享资源对象
	current = current.duplicate(true)
	current.set(prop, value)
	style_changed.emit()

func apply_style(style: InkBrushStyle) -> void:
	if style == null:
		return
	current = style.duplicate(true)
	style_changed.emit()

func save_user() -> Error:
	if current == null:
		return ERR_UNAVAILABLE
	return ResourceSaver.save(current, USER_PATH)

func save_res() -> Error:
	if current == null or not OS.has_feature("editor"):
		return ERR_UNAVAILABLE
	return ResourceSaver.save(current, RES_PATH)

func reset_default() -> void:
	current = InkBrushStyle.new()
	style_changed.emit()

func reload_from_disk() -> void:
	current = _load_active()
	style_changed.emit()
