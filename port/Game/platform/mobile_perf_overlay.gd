extends CanvasLayer
## 临时工具：手机端画质实测用的屏幕读数。只在 mobile 的 debug 包里出现。
##
## 用途是给移植调档位提供实测数据（帧率、绘制调用、显存、物理耗时），
## 不参与玩法，交付前删除本文件与 main.gd 里的挂载。

const SAMPLE_SECONDS: float = 1.0

var _label: Label
var _frames: int = 0
var _elapsed: float = 0.0
var _fps: float = 0.0
var _low: float = 0.0


func _ready() -> void:
	layer = 128
	_label = Label.new()
	_label.position = Vector2(12, 8)
	_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, .85))
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)
	_update_text()


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
	_label.text = "FPS %.0f  最低 %.0f\n绘制 %d  顶点 %.1fM\n显存 %.0f MB  物理 %.2f ms\n启动阶段 %s\n%s / %s\n窗口 %s" % [
		_fps,
		_low,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000000.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		stage,
		backend,
		RenderingServer.get_video_adapter_name(),
		str(get_viewport().get_visible_rect().size),
	]