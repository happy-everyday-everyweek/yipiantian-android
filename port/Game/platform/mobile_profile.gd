extends RefCounted
## Android 端的平台画质策略。桌面导出也会实例化，但只在 mobile 特性下生效。
##
## 单一职责：只放"手机与桌面不同"的那部分——抗锯齿方式、上采样方式、屏幕常亮、
## 默认渲染分辨率。取景相关的后处理档位归 focus_detail，渲染倍率归 main.gd 的
## _apply_render_resolution，帧率预算仍归 window_activity。

## 手机默认 720p 渲染再上采样：这台设备约 0.62 倍分辨率，顶点与填充压力一起下降；
## 用户在设置里仍可切原生或 1080p 折中。
const DEFAULT_RESOLUTION: String = "720"
## 桌面用"输出高度"表达分辨率；手机屏幕纵向像素远多于桌面窗口，按高度换算会接近 1 倍，
## 所以手机直接给 3D 渲染倍率：720p≈0.62、1080p≈0.85、原生及以上=1.0。
const RENDER_SCALE: Dictionary = {"native": 1.0, "720": 0.62, "1080": 0.85, "1440": 1.0, "2160": 1.0}


func render_scale(choice: String) -> float:
	return RENDER_SCALE.get(choice, 0.85)

func is_mobile() -> bool:
	return OS.has_feature("mobile")


static func dof_allowed(quality: String) -> bool:
	# 景深是整屏代价。桌面维持原档位语义（低画质停用）；
	# 手机只在"高画质"保留，其余档位停用，UI 与渲染共用这一处判定。
	if OS.has_feature("mobile"):
		return quality == "high"
	return quality != "low"


func apply(viewport: Viewport) -> void:
	if viewport == null or not is_mobile():
		return
	# MSAA 在移动 GPU 上是纯带宽开销，边缘交给 FXAA。
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	# 非原生分辨率下用 FSR 上采样；FSR 只在 Vulkan 后端可用，OpenGL 退回双线性。
	if RenderingServer.get_rendering_device() != null:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	else:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	# 手机没有稳定的"窗口失焦"状态，前台帧率仍由 window_activity 收放。
	Engine.max_fps = 45
	DisplayServer.screen_set_keep_on(true)
