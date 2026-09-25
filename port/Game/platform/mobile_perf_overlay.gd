extends CanvasLayer
## 临时诊断面板：手机 debug 包专用。用来在现场逐项关掉可疑开销，直接看帧率与画面的变化。
## 交付前删除本文件、main.gd 里的挂载，以及 focus_detail 里的曝光分支。

const SAMPLE_SECONDS: float = 1.0
const RENDER_SCALES: Array = [0.5, 0.62, 0.85, 1.0]
const EXPOSURES: Array = [0.9, 1.0, 1.15, 1.3]

var _label: Label
var _sun: DirectionalLight3D
var _water: Node
var _plants: Node3D
var _islets: Node3D
var _environment: Environment
var _frames: int = 0
var _elapsed: float = 0.0
var _fps: float = 0.0
var _low: float = 0.0


func _ready() -> void:
	layer = 128
	var main: Node = get_parent()
	_sun = main.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	var courtyard: Node = main.get_node_or_null("Environment")
	if courtyard != null:
		if courtyard.has_method("get_water_surface"):
			_water = courtyard.call("get_water_surface")
		_plants = courtyard.get_node_or_null("PlayerPlants")
		_islets = courtyard.get_node_or_null("NeighborIslets")
	var world: WorldEnvironment = main.get_node_or_null("WorldEnvironment")
	if world != null:
		_environment = world.environment
	_label = Label.new()
	_label.position = Vector2(12, 8)
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, .85))
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)
	var panel := VBoxContainer.new()
	panel.position = Vector2(12, 170)
	panel.add_theme_constant_override("separation", 6)
	add_child(panel)
	_row(panel, [["阴影", _toggle_shadow], ["水面", _toggle_water], ["远景", _toggle_islets], ["作物", _toggle_plants]])
	var scales := HBoxContainer.new()
	scales.add_theme_constant_override("separation", 6)
	panel.add_child(scales)
	scales.add_child(_tag("倍率"))
	for value in RENDER_SCALES:
		scales.add_child(_button("%.2f" % value, func() -> void: _set_scale(value)))
	var exposures := HBoxContainer.new()
	exposures.add_theme_constant_override("separation", 6)
	panel.add_child(exposures)
	exposures.add_child(_tag("曝光"))
	for value in EXPOSURES:
		exposures.add_child(_button("%.2f" % value, func() -> void: _set_exposure(value)))
	_update_text()


func _row(parent: Node, entries: Array) -> void:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)
	for entry in entries:
		box.add_child(_button(entry[0], entry[1]))


func _tag(text: String) -> Label:
	var tag := Label.new()
	tag.text = text
	tag.add_theme_font_size_override("font_size", 14)
	tag.add_theme_color_override("font_color", Color(1, 1, 1))
	tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, .85))
	tag.add_theme_constant_override("outline_size", 5)
	tag.custom_minimum_size = Vector2(44, 0)
	return tag


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(76, 34)
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(action)
	return button


func _toggle_shadow() -> void:
	if _sun != null:
		_sun.shadow_enabled = not _sun.shadow_enabled


func _toggle_water() -> void:
	if _water is Node3D:
		(_water as Node3D).visible = not (_water as Node3D).visible


func _toggle_islets() -> void:
	if _islets != null:
		_islets.visible = not _islets.visible


func _toggle_plants() -> void:
	if _plants != null:
		_plants.visible = not _plants.visible


func _set_scale(value: float) -> void:
	get_viewport().scaling_3d_scale = value


func _set_exposure(value: float) -> void:
	if _environment != null:
		_environment.tonemap_exposure = value


func _process(delta: float) -> void:
	_frames += 1
	_elapsed += delta
	if _elapsed >= SAMPLE_SECONDS:
		var sample: float = float(_frames) / _elapsed
		_fps = sample if _fps <= 0.0 else lerpf(_fps, sample, .5)
		_low = sample if _low <= 0.0 else minf(_low, sample)
		_frames = 0
		_elapsed = 0.0
		_update_text()


func _update_text() -> void:
	var stage: String = str(Engine.get_meta("boot_stage", "未记录"))
	var backend: String = "Vulkan" if RenderingServer.get_rendering_device() != null else "OpenGL"
	_label.text = "FPS %.0f  最低 %.0f  CPU %.1f ms\n绘制 %d  顶点 %.1fM  显存 %.0f MB\n启动 %s\n%s / %s\n倍率 %.2f  曝光 %.2f  窗口 %s" % [
		_fps,
		_low,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000000.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		stage,
		backend,
		RenderingServer.get_video_adapter_name(),
		get_viewport().scaling_3d_scale,
		_environment.tonemap_exposure if _environment != null else 0.0,
		str(get_viewport().get_visible_rect().size),
	]