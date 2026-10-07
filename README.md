# TogetherPlayer iPad build

独立的公开 iPad 构建源码仓库，用于 GitHub 标准 macOS runner 构建未签名 IPA。包含 iPad 应用、回归测试、固定依赖及构建脚本。

不包含服务器部署、路由器配置、会话数据库、运行日志、影片、用户字幕、OAuth 授权、签名证书或私有仓库历史。第三方依赖许可证见 ios/TogetherPoC.swiftpm/Licenses。

在 Actions → Build iPad unsigned IPA 查看测试和安装包。公开仓库的标准 GitHub 托管 runner 通常免费；账户级账单限制仍可能阻止运行，以实际结果为准。

当前版本：TogetherPlayer 0.4.6 / build46。基于已交付 0.4.5 的源码提交 8384fbdcb4638a6a1114adb7b26da207086c1aad，保留弹幕键盘适配、剩余时间和不同画质匹配。

0.4.6 构建源码提交 5c37ad27005a8d278d2211db8d2bcb77120c4d1f；47 项原生单元测试、11 项界面测试全部通过。包含外挂字幕文件选择修复、原资源内置文字字幕读取和切换、MKV 音轨信息。

验证和下载：https://github.com/Qq20050817/togetherplayer-ipad-build/actions/runs/37640748833
