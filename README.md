# TogetherPlayer iPad build

独立的公开 iPad 构建源码仓库，用于 GitHub 标准 macOS runner 构建未签名 IPA。包含 iPad 应用、回归测试、固定依赖及构建脚本。

不包含服务器部署、路由器配置、会话数据库、运行日志、影片、用户字幕、OAuth 授权、签名证书或私有仓库历史。第三方依赖许可证见 ios/TogetherPoC.swiftpm/Licenses。

在 Actions → Build iPad unsigned IPA 查看测试和安装包。公开仓库的标准 GitHub 托管 runner 通常免费；账户级账单限制仍可能阻止运行，以实际结果为准。

当前版本：TogetherPlayer 0.4.7 / build47。基于已交付 0.4.6，保留字幕导入、原资源字幕与音轨读取、服务器恢复暂停，以及弹幕键盘适配、剩余时间和不同画质匹配。

新增统一字幕调整面板：时间偏移每次 0.1 秒，垂直位置与 16–64 字号调整、预览和恢复默认。内置文字字幕与外挂字幕共用设置；字号和位置保存，换片重置时间偏移。

0.4.7 构建源码提交 2e4195dd1a162fcc875eb2373811995f9be193e9；51 项原生单元测试、12 项界面测试全部通过。实际 MKV 原字幕输出、偏移和字幕到期消失，以及普通/全屏调整面板操作已验证。

验证和下载：https://github.com/Qq20050817/togetherplayer-ipad-build/actions/runs/37660863466

ASS/SSA 按文字显示，复杂排版与图片字幕不保证原样呈现。
