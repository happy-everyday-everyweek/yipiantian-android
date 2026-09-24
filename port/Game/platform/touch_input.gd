extends RefCounted
## 触摸手势翻译层：把手势翻译成与桌面输入一致的镜头意图。
##
## 点按与控件仍然走项目的 emulate_mouse_from_touch（手指按下即鼠标左键），
## 这里只补桌面鼠标没有的三件事：单指拖动旋转视角、双指捏合缩放、双指拖动平移，
## 以及用"按住不动"代替右键／Esc 的取消与返回。镜头状态仍由 FarmCamera 拥有。

## 手势开始：调用方在这里收尾上一次点按（清空待判定点击队列、结束悬停手势）。
signal gesture_began
signal orbit(relative: Vector2)
signal pan(relative: Vector2)
signal zoom(amount: float)
signal long_press

## 与桌面同一口径：位移小于这个距离视为点按，不产生镜头动作。
const TAP_SLOP: float = 7.0
## 手指移动比鼠标快得多，按同一角度系数会一步转到边界。
const ORBIT_SCALE: float = 0.55
const LONG_PRESS_SECONDS: float = 0.5
## 双指间距每变化一像素换算成的镜头距离，与滚轮一档（0.8）同量级。
const PINCH_DISTANCE_PER_PIXEL: float = 0.02

var _touches: Dictionary = {}
var _travel: float = 0.0
var _orbiting: bool = false
var _multi: bool = false
var _pinch_span: float = -1.0
var _multi_center: Vector2 = Vector2.INF
var _hold_seconds: float = 0.0
var _hold_pending: bool = false


## 每帧推进长按计时；只有"一根手指、没动、没有第二根手指"才算长按。
func advance(delta: float) -> void:
	if not _hold_pending or _touches.size() != 1 or _orbiting or _multi:
		return
	_hold_seconds += delta
	if _hold_seconds >= LONG_PRESS_SECONDS:
		_hold_pending = false
		_orbiting = true
		long_press.emit()


## 返回 true 表示这次事件已被手势接管，调用方应停止继续扩散。
func handle(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		return _handle_touch(event)
	if event is InputEventScreenDrag:
		return _handle_drag(event)
	return false


func _handle_touch(event: InputEventScreenTouch) -> bool:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_begin_single(event.position)
		else:
			_begin_multi()
		return true
	_touches.erase(event.index)
	if _touches.is_empty():
		_reset()
	elif _touches.size() == 1:
		# 捏合结束后剩一根手指时保持"已接管"，避免抬手瞬间变成误旋转或误点按。
		_orbiting = true
		_pinch_span = -1.0
	return true


func _handle_drag(event: InputEventScreenDrag) -> bool:
	_touches[event.index] = event.position
	if _touches.size() >= 2:
		_drag_multi()
		return true
	_travel += event.relative.length()
	if not _orbiting and _travel > TAP_SLOP:
		_orbiting = true
		_hold_pending = false
		gesture_began.emit()
	if _orbiting:
		orbit.emit(event.relative * ORBIT_SCALE)
	return _orbiting


func _begin_single(position: Vector2) -> void:
	_travel = 0.0
	_orbiting = false
	_multi = false
	_pinch_span = -1.0
	_multi_center = Vector2.INF
	_hold_seconds = 0.0
	_hold_pending = true
	# position 只用于将来可能的"长按位置"，当前长按等价于取消，不需要坐标。
	if not is_finite(position.x):
		_hold_pending = false


func _begin_multi() -> void:
	# 第二根手指落下即放弃点按判定：抬起时不应该再触发田块或农具。
	_multi = true
	_orbiting = true
	_hold_pending = false
	_pinch_span = -1.0
	_multi_center = Vector2.INF
	gesture_began.emit()


func _drag_multi() -> void:
	var points: Array[Vector2] = []
	for index: Variant in _touches:
		points.append(_touches[index])
		if points.size() == 2:
			break
	if points.size() < 2:
		return
	var span: float = points[0].distance_to(points[1])
	var center: Vector2 = (points[0] + points[1]) * 0.5
	if _pinch_span > 0.0:
		var amount: float = (_pinch_span - span) * PINCH_DISTANCE_PER_PIXEL
		if absf(amount) > 0.0001:
			zoom.emit(amount)
	if _multi_center.is_finite():
		var offset: Vector2 = center - _multi_center
		if offset.length_squared() > 0.0:
			pan.emit(offset)
	_pinch_span = span
	_multi_center = center


func _reset() -> void:
	_travel = 0.0
	_orbiting = false
	_multi = false
	_pinch_span = -1.0
	_multi_center = Vector2.INF
	_hold_seconds = 0.0
	_hold_pending = false