# Android 0.5.8：本地 Main10 兼容播放与同剪辑转码版

正常片源继续使用 Media3。仅本地 file/content 的 HEVC Main10 视频发生解码失败时，启用 LibVLC 3.6.5 的独立软件视频解码（avcodec），不再重复调用失败的 c2.android.hevc.decoder。网络片源沿用原路径。

兼容准备时静音解码第一帧；获得真实显示帧后按房间状态播放或暂停。暂停、跳转、音量、语音平滑静音、外挂字幕及内置选轨继续由现有界面控制。不会自动创建房间、重置数据库或修改同步服务。4K 软件解码流畅程度取决于设备算力，云端格式测试不能代替目标小米平板的原片验收。

安卓本地文件指纹不同时，不再直接拒绝：显示原版与所选文件名，用户确认相同内容和剪辑后，绑定当前房间影片身份并核对时长。时长扣除本机时间校准后允许 5 秒容器误差；未知时长及明显不一致时保持暂停、不上报准备就绪。文件名或时长相近不能证明同一剪辑，必须人工确认。房间或片源在确认期间变化则不应用旧选择。iPad 已有对应确认功能，本次不修改 iPad。

## 验证

阶段一：云端 Android API35 独立 LibVLC 显示真实 3840×2076、HEVC Main10 测试帧；1 项原生测试通过（run 38140557743）。测试片由 testsrc2 生成，2fps，仅验证格式解码，不能证明电影帧率的流畅程度。

阶段二：集成播放器真实帧、暂停不自动恢复、跳转、音量与换片回归；实际文件指纹不同的确认弹窗和真实时长核对；沿用全部原生界面/语音/字幕测试与同步单元测试。结果以发布目录验证报告为准。

## 开源依赖

LibVLC Android 3.6.5（LGPL-2.1-or-later）：
- 项目与构建源码：https://code.videolan.org/videolan/vlc-android
- 引擎源码：https://code.videolan.org/videolan/vlc
- Maven 源与二进制：https://repo.maven.apache.org/maven2/org/videolan/android/libvlc-all/3.6.5/

未修改 LibVLC 或其 JNI 库。完整应用源及构建文件随交付提供，可替换依赖并重建。许可证文件位于 licenses/LGPL-2.1-LibVLC.txt。其他原有 Vosk / Jellyfin FFmpeg 依赖许可沿用原交付。

用户交付构建使用 `gradle -p android assembleDebug -PdeliveryArm64=true`，仅保留 arm64-v8a，减小下载体积；云端原生测试仍保留 x86_64。
