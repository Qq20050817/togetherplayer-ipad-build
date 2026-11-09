# AI Issues

每条问题需记录：ID、时间、影响范围与版本、复现步骤、可核实的报错、根因（未知则写未知）、修复提交、回归验证、当前状态。

初始化时尚未逐项验证历史故障。过去聊天或文档中的问题应按 GitHub 代码、测试和实际运行证据重新核对，不能自动标为「已解决」。

## 2026-11-09 · Router USB deletion

Baseline `cae70b34d84b163061ae8967eb8a02ef7125d14e`; branch `feat/ipad-router-usb-delete-0659`. iPad 0.6.59 successful Actions run 39690482361 used instead of stale 0.4.8 main. Native USB management view, session login, browsing, confirmation and verified delete response. Native build pending. Production USB not modified; current mount health and write policy unverified. No installation or deployment claimed. Rollback: keep original branch / disable deleteEnabled.
