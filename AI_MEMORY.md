# AI MEMORY

## 已核实的仓库事实

- 此仓库是公开的 TogetherPlayer iPad 构建源码及 GitHub Actions 构建仓库。
- `main` 的 README 仍介绍较早版本，不能当作最新已交付 iPad 客户端。每次根据已成功构建的 IPA、Actions、准确提交及版本文件核对基线。
- 与私有主仓库的源码可能不同步，不能自动以任一 `main` 替换已发布客户端。

## 公开仓库边界

- 禁止添加凭据、私人仓库历史、私有服务器路径、生产日志、影片、字幕、证书和用户信息。
- 保留测试、签名边界和构建流程，代码修改优先独立分支与可复现验证。

## 维护原则

记录不敏感的长期决策，实际结果参照准确构建日志和提交 SHA。

## 2026-11-09 · Router USB deletion

Baseline `cae70b34d84b163061ae8967eb8a02ef7125d14e`; branch `feat/ipad-router-usb-delete-0659`. iPad 0.6.59 successful Actions run 39690482361 used instead of stale 0.4.8 main. Native USB management view, session login, browsing, confirmation and verified delete response. Native build pending. Production USB not modified; current mount health and write policy unverified. No installation or deployment claimed. Rollback: keep original branch / disable deleteEnabled.
