extends CanvasLayer
## 临时诊断面板 + 本机日志/控制通道（手机 debug 包专用，交付前整文件删除）。
##
## 面板：现场逐项关掉可疑开销，直接看帧率与画面变化。
## 通道：监听 127.0.0.1，用 curl 就能读引擎日志（含着色器编译错误）、查状态、远程改参数。
##   读取日志： curl http://127.0.0.1:8791/log
##   查看状态： curl http://127.0.0.1:8791/state
##   远程调整： curl 'http://127.0.0.1:8791/cmd?exposure=0.9&scale=0.62&shadows=0'

const SAMPLE_SECONDS: float = 1.0
const PORT: int = 8791
const LOG_TAIL_LINES: int = 500
## 日志与状态的外置镜像目录（Write 分享用）。需要用户授予「所有文件访问」，
## 未授权时写入失败，会自动退回只保留 user:// 内的引擎日志。
const EXPORT_DIR: String = "/storage/emulated/0/Download/yipiantian/logs"
const EXPORT_LOG: String = EXPORT_DIR + "/godot.log"
const EXPORT_STATE: String = EXPORT_DIR + "/state.txt"
const MIRROR_SECONDS: float = 1.5
const RENDER_SCALES: Array = [0.5, 0.62, 0.85, 1.0]
const EXPOSURES: Array = [0.9, 1.0, 1.15, 1.3]

var _label: Label
var _sun: DirectionalLight3D
var _water: Node
var _plants: Node3D
var _islets: Node3D
var _environment: Environment
var _server: TCPServer
var _clients: Array[StreamPeerTCP] = []
var _frames: int = 0
var _elapsed: float = 0.0
var _mirror_elapsed: float = 0.0
var _export_ok: bool = false
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
	_server = TCPServer.new()
	if _server.listen(PORT, "127.0.0.1") == OK:
		print("DIAG_READY 127.0.0.1:%d" % PORT)
	else:
		push_warning("诊断端口监听失败")
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
	_serve_clients()
	_frames += 1
	_elapsed += delta
	_mirror_elapsed += delta
	if _mirror_elapsed >= MIRROR_SECONDS:
		_mirror_elapsed = 0.0
		_mirror_exports()
	if _elapsed >= SAMPLE_SECONDS:
		var sample: float = float(_frames) / _elapsed
		_fps = sample if _fps <= 0.0 else lerpf(_fps, sample, .5)
		_low = sample if _low <= 0.0 else minf(_low, sample)
		_frames = 0
		_elapsed = 0.0
		_update_text()


func _serve_clients() -> void:
	if _server == null:
		return
	while _server.is_connection_available():
		var peer: StreamPeerTCP = _server.take_connection()
		if peer != null:
			_clients.append(peer)
	var index: int = _clients.size() - 1
	while index >= 0:
		var peer: StreamPeerTCP = _clients[index]
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.remove_at(index)
		elif peer.get_available_bytes() > 0:
			_respond(peer, peer.get_utf8_string(peer.get_available_bytes()))
			_clients.remove_at(index)
		index -= 1


func _respond(peer: StreamPeerTCP, request: String) -> void:
	var first_line: String = request.split("\n")[0].strip_edges()
	var parts: PackedStringArray = first_line.split(" ")
	var path: String = parts[1] if parts.size() > 1 else "/"
	var body: String = ""
	if path.begins_with("/log"):
		body = _log_tail()
	elif path.begins_with("/state"):
		body = _state_text()
	elif path.begins_with("/cmd"):
		body = _apply_command(path)
	else:
		body = "用法：/log 读日志；/state 看状态；/cmd?exposure=0.9&scale=0.62&shadows=0&glow=0&water=0&islets=0&plants=0"
	var payload: PackedByteArray = body.to_utf8_buffer()
	var head: String = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % payload.size()
	peer.put_data(head.to_utf8_buffer() + payload)


func _log_tail() -> String:
	var path: String = ProjectSettings.globalize_path("user://logs/godot.log")
	if not FileAccess.file_exists(path):
		return "（没有日志文件：%s）" % path
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "（日志打不开）"
	var lines: PackedStringArray = file.get_as_text().split("\n")
	if lines.size() > LOG_TAIL_LINES:
		lines = lines.slice(lines.size() - LOG_TAIL_LINES)
	return "\n".join(lines)


func _mirror_exports() -> void:
	# 引擎日志与状态镜像到 Download，方便直接查看和分享；没授权时写入失败并自我记录。
	if not DirAccess.dir_exists_absolute(EXPORT_DIR):
		DirAccess.make_dir_recursive_absolute(EXPORT_DIR)
	_write_text(EXPORT_LOG, _log_tail())
	_write_text(EXPORT_STATE, _state_text())


func _write_text(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_export_ok = false
		return
	file.store_string(text)
	file.close()
	_export_ok = true


func _state_text() -> String:
	return "fps=%.1f low=%.1f cpu_ms=%.1f draws=%d verts=%.1fM vmem=%.0fMB\nexport=%s\nscale=%.2f exposure=%.2f backend=%s gpu=%s\nshadows=%s water=%s islets=%s plants=%s glow=%s" % [
		_fps,
		_low,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000000.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		str(_export_ok),
		get_viewport().scaling_3d_scale,
		_environment.tonemap_exposure if _environment != null else 0.0,
		"Vulkan" if RenderingServer.get_rendering_device() != null else "OpenGL",
		RenderingServer.get_video_adapter_name(),
		str(_sun.shadow_enabled) if _sun != null else "?",
		str((_water as Node3D).visible) if _water is Node3D else "?",
		str(_islets.visible) if _islets != null else "?",
		str(_plants.visible) if _plants != null else "?",
		str(_environment.glow_enabled) if _environment != null else "?",
	]


func _apply_command(path: String) -> String:
	var query: String = path.split("?", true, 1)[1] if path.contains("?") else ""
	var lines: PackedStringArray = []
	for pair: String in query.split("&"):
		var kv: PackedStringArray = pair.split("=")
		if kv.size() != 2:
			continue
		var key: String = kv[0]
		var value: String = kv[1]
		match key:
			"scale":
				get_viewport().scaling_3d_scale = clampf(value.to_float(), 0.25, 2.0)
				lines.append("scale=%.2f" % get_viewport().scaling_3d_scale)
			"exposure":
				if _environment != null:
					_environment.tonemap_exposure = clampf(value.to_float(), 0.2, 3.0)
					lines.append("exposure=%.2f" % _environment.tonemap_exposure)
			"glow":
				if _environment != null:
					_environment.glow_enabled = value != "0"
					lines.append("glow=%s" % str(_environment.glow_enabled))
			"shadows":
				if _sun != null:
					_sun.shadow_enabled = value != "0"
					lines.append("shadows=%s" % str(_sun.shadow_enabled))
			"water":
				if _water is Node3D:
					(_water as Node3D).visible = value != "0"
					lines.append("water=%s" % str((_water as Node3D).visible))
			"islets":
				if _islets != null:
					_islets.visible = value != "0"
					lines.append("islets=%s" % str(_islets.visible))
			"plants":
				if _plants != null:
					_plants.visible = value != "0"
					lines.append("plants=%s" % str(_plants.visible))
			"fps":
				Engine.max_fps = maxi(value.to_int(), 10)
				lines.append("max_fps=%d" % Engine.max_fps)
			_:
				lines.append("未知参数 " + key)
	return "\n".join(lines) if not lines.is_empty() else "没有可用参数"


func _update_text() -> void:
	var stage: String = str(Engine.get_meta("boot_stage", "未记录"))
	var backend: String = "Vulkan" if RenderingServer.get_rendering_device() != null else "OpenGL"
	_label.text = "FPS %.0f  最低 %.0f  CPU %.1f ms\n绘制 %d  顶点 %.1fM  显存 %.0f MB\n启动 %s\n%s / %s  端口 %d  外写 %s\n倍率 %.2f  曝光 %.2f  窗口 %s" % [
		_fps,
		_low,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000000.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		stage,
		backend,
		RenderingServer.get_video_adapter_name(),
		PORT,
		str(_export_ok),
		get_viewport().scaling_3d_scale,
		_environment.tonemap_exposure if _environment != null else 0.0,
		str(get_viewport().get_visible_rect().size),
	]