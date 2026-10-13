# iPad PGS 字幕：观看路径与 AI OCR 索引路径隔离（试验中）

基线：已通过 GitHub Actions 的 iPad 0.6.14 源码提交 `642db346e18ab3aba0bbf3bf6d0bb9df652d0f09`。本功能独立开发，不修改既有服务端、安卓、播放器媒体文件或发布分支。

## 用户期望
- **观看**：继续播放原始电影文件，保留选中的字幕轨道；不因 AI OCR 切换字幕、覆盖/写回 PGS 或强制使用 SRT 显示。
- **AI**：当播放源的 PGS 已被读取并经 OCR 转成文本时，在内存中转成等效 SRT（保留提示文字和时间码）；交给独立剧情证据/时间轴索引；跳播到未观看片段不会提前出题。
- **失败回退**：OCR 出错或字幕段缺失时仅使 AI 少一部分证据；不能改变播放字幕或阻止播放。
- **隐私**：转换文本在本机处理；除既有已授权的云端剧情请求外，不上传整部电影字幕。

## 当前接通的代码路径
- 固定的 PrismCore 版本在 PGS-only MKV remux 时会用 Vision OCR 产生 HLS WebVTT；条件是源影片没有文本字幕轨道。此路径不保证所有 PGS 都有可索引的 OCR 成果。
- `MKVRemux.pgsOCRRendition` 仅识别上述「PGS 且无原生文本字幕」的典型条件。
- `TestClient.prepareNativeSubtitleIndex` 使用现有 HLS WebVTT 索引能力，将这一路径标注为 `forAIOnly`。
- `ExternalSubtitles.nativeAISRT` 保存内存中的 SRT 字符串。AI 仍使用等效的 `SubtitleDocument` 时间码与证据；**不能因索引成功就把 OCR 文本直接作为用户选择的原生显示字幕**。
- 播放器/房间的字幕选中状态与电影源文件都不变；已有文本字幕的显示/索引逻辑保持兼容。

## 尚未完成（不可声称已支持原版 PGS 显示）
**关键边界：** 当前 PrismCore 的 HLS remux 已用 OCR WebVTT 呈现部分 PGS；它并没有向 TogetherPlayer 的 AVPlayer 显示层交付原始 PGS 位图。因此虽然此改动隔离了**额外 AI 索引**，仍无法证明观看者看到的是像素级原版 PGS。完整实现需要独立的 PGS 位图提取与透明叠加绘制通道（或底层解码库提供等效原始位图输出），并在真机测试选轨、HDR、全屏、进度跳转、重连。

还需覆盖源中「PGS + 原生文本字幕」并存的情况、含字体效果/双语字幕的 OCR 误识别、整片大容量字幕索引对播放流畅度的影响，以及实际电影 OCR 命中率。模拟器的 Swift 单元测试只验证轨道分离和 SRT 时间格式，不能替代原版 PGS 显示验收。

## 回滚
保留原验证提交 `642db346e18ab3aba0bbf3bf6d0bb9df652d0f09` 和 0.6.14 IPA；新分支问题直接恢复之前的 IPA/分支即可。不部署、不替换服务。
