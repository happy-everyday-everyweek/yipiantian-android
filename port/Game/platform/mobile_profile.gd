extends RefCounted
## Android 端的平台画质策略。桌面导出也会实例化，但只在 mobile 特性下生效。
##
## 单一职责：只放"手机与桌面不同"的那部分——抗锯齿方式、上采样方式、屏幕常亮、
## 默认渲染分辨率。取景相关的后处理档位归 focus_detail，渲染倍率归 main.gd 的
## _apply_render_resolution，帧率预算仍归 window_activity。

## 手机默认 1080 渲染再上采样：1260 高的屏幕约 0.86 倍，移动 GPU 收益最直接；
## 用户在设置里仍可切原生（更清晰）或 720p（更省电）。
const DEFAULT_RESOLUTION: String = "1080"

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
	# 非原生分辨率下用 FSR 上采样，成本接近双线性但明显更清晰。
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	# 手机没有稳定的"窗口失焦"状态，前台帧率仍由 window_activity 收放。
	Engine.max_fps = 60
	DisplayServer.screen_set_keep_on(true)
