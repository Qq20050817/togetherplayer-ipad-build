# TogetherPlayer iPad build

独立的公开 iPad 构建源码仓库，用于 GitHub 标准 macOS runner 构建未签名 IPA。包含 iPad 应用、回归测试、固定依赖及构建脚本。

不包含服务器部署、路由器配置、会话数据库、运行日志、影片、用户字幕、OAuth 授权、签名证书或私有仓库历史。第三方依赖许可证见 ios/TogetherPoC.swiftpm/Licenses。

在 Actions → Build iPad unsigned IPA 查看测试和安装包。公开仓库的标准 GitHub 托管 runner 通常免费；账户级账单限制仍可能阻止运行，以实际结果为准。

发布候选版：TogetherPlayer **0.6.1 / build61**（2026-10-13）。基于已通过的全屏手势修复，修复退出全屏清理流程。iPad 构建成功，83 项核心测试 + 5 项关键界面测试通过，其中连续 3 次退出全屏的防闪退检查通过；仍需在真实 iPad 上验收，并自行使用受信任证书签名 IPA。未合并正式分支。

- iPad 构建源码提交：`107ef6b4c3e2c5df62752cdb8b18fbb250e8a351`
- [iPad 未签名安装包及成功测试](https://github.com/Qq20050817/togetherplayer-ipad-build/actions/runs/38281836733)
- [Android v0.6.1 构建及 24 项模拟器测试](https://github.com/Qq20050817/togetherplayer-ipad-build/actions/runs/38281833915)
- 修复分支：`release/v0.6.1-fullscreen-exit-20261013`；前一成功基线：`3f262261296bcb86cda7bd265f0bdfd925bcadc0`。

历史版本：TogetherPlayer 0.4.8 / build48。保留字幕导入、原资源字幕与音轨读取、服务器恢复暂停，以及弹幕键盘适配、剩余时间和不同画质匹配。

字幕改为透明背景、白字与轻微黑色阴影，默认系统常规字体。字幕调整 → 字体与间距：系统／圆体／衬线、四档粗细、字距 -2 至 +6（步长 0.25）、行距 -8 至 +20（步长 0.5）。带两行文字预览，设置持久保存，支持恢复默认。内置文字字幕与外挂字幕共用样式。

保留字幕时间偏移每次 0.1 秒、垂直位置和 16–64 字号调整。换片或导入新字幕重置时间偏移。

0.4.8 构建源码提交 c4dc73172b60756ed5083cc363e9ce1ad5270be2；51 项原生单元测试、12 项界面测试全部通过。实际 MKV 原字幕输出、偏移和字幕到期消失，以及普通/全屏字体与间距操作已验证。

验证和下载：https://github.com/Qq20050817/togetherplayer-ipad-build/actions/runs/37698101966

系统字体可能按语言回退，不承诺与 Infuse 字体完全相同。ASS/SSA 按文字显示，复杂排版与图片字幕不保证原样呈现。
