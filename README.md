# 我有一片田 · Android 移植改动

这个仓库只放移植改动和构建工作流，不复制上游源码。工作流会克隆上游
`henjicc/yipiantian`（含 Git LFS 资产），把 `port/` 覆盖上去，再用 Godot 4.7.2
导出 Android 调试版 APK，产物在 Actions 的 artifact 里。

上游是 Windows 桌面游戏，仓库不含许可证文件，因此本仓库保持私有，只作为个人移植工作区。

## 改动内容

`port/Game/project.godot` 增加手机平台覆盖：渲染方式在 mobile 上切到 Mobile 渲染器，
窗口拉伸改为 expand 以适配手机屏幕比例，并让手机端保持屏幕常亮。桌面导出不受影响。

`port/Game/platform/mobile_profile.gd` 是新增的手机端平台策略，负责关闭 MSAA 改用
FXAA、启用 FSR 上采样、设置手机侧帧率上限与屏幕常亮，并提供景深可用档位的单一判定，
供 UI 与渲染共用。

`port/Game/presentation/focus_detail.gd` 在原有低／标准／高三档基础上加了手机分支：
关闭 MSAA，阴影图集减半，关闭屏幕空间遮蔽，间接光只在桌面高档启用。

`port/Game/platform/touch_input.gd` 是新增的触摸手势层，把手势翻译成与桌面一致的镜头
意图：单指拖动旋转视角、双指捏合缩放、双指拖动平移、长按代替右键与 Esc 的取消返回。
点按与界面控件仍走项目的触摸转鼠标，因此按钮、田格与农具的点击行为没有改动。

`port/Game/scenes/main.gd` 负责接线：装载手机策略与手势层，并在非处理输入阶段把
手势事件交给手势层，在物理帧推进长按计时。

`port/Game/ui/game_menu.gd` 与 `port/Game/ui/camera_tuning.gd` 在手机端隐藏桌面壁纸
入口，景深开关按当前画质显示为可用或停用。`port/Game/settings/settings_store.gd` 与
菜单一起新增 720p 渲染分辨率选项，便于在手机上换取帧率。

导出预设 `port/Game/export_presets.cfg` 新增 Android 预设：只出 arm64，关闭 gradle
构建，纹理使用 ETC2/ASTC，包名 `com.henjicc.yipiantian`。

`port/Game/platform/mobile_perf_overlay.gd` 是临时工具，只在手机 debug 包里显示帧率、
绘制调用、显存与物理耗时，用于实测调档位，交付前会删除。
