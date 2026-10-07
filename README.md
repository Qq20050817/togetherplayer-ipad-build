# TogetherPlayer iPad build

独立的公开 iPad 构建源码仓库，用于 GitHub 标准 macOS runner 构建未签名 IPA。包含 iPad 应用、回归测试、固定依赖及构建脚本。

不包含服务器部署、路由器配置、会话数据库、运行日志、影片、用户字幕、OAuth 授权、签名证书或私有仓库历史。第三方依赖许可证见 ios/TogetherPoC.swiftpm/Licenses。

在 Actions → Build iPad unsigned IPA 查看测试和安装包。公开仓库的标准 GitHub 托管 runner 通常免费；账户级账单限制仍可能阻止运行，以实际结果为准。

源码基线：TogetherPlayer 0.4.5 / build45，原始应用源码提交 f691fd4205e527c38415ab35272fe5cf3cf355e6。
