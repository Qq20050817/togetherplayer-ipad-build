# TogetherPlayer P2P 快通道实验（第一阶段）

状态：**仅在独立实验分支内开发，未开启正式播放器 P2P 同步，暂不提供安装包。**

## 源码基线

- iPad：`fix/ipad-genre-test-isolation-20261018`，提交 `bca85969c2312d42dae0302e68e1862a26302bee`，iPad 0.6.49。
- Android：`feat/android-visual-recap-review-20261017`，提交 `aa294c7aa0f1dd9d7aab01a27f7ebebbeb1bdda1`，Android 0.6.10。
- 实验分支：`experiment/p2p-fastpath-ipad-20261018` 与 `experiment/p2p-fastpath-android-20261018`。
- 先前 Cloudflare 独立浏览器 WebRTC 测试：两人跨网络 P2P DataChannel 建立成功，用户报告 79ms 往返中位数、14 条消息、0 超时；尚未证明具体采用 IPv6，未进行正式播放验证。

## 核心设计

1. **Muse 始终权威**：房间身份/权限、成员名单、影片身份、时间轴版本、播放 ACK、结算和历史仍走 Muse。现有同步通道不能关闭。
2. **WebRTC 仅负责快速控制**：允许携带 `PLAY/PAUSE/SEEK` 的短指令，绝不传视频、字幕、百度网盘令牌或电影文件。
3. **默认拒绝**：P2P 连上不等于获得房间权限。必须与 Muse 的房间成员身份进行绑定并证明另一端持有该身份后，才将 `peerVerified` 设为 true；现有浏览器随机邀请房间尚不满足此项。
4. **短期乐观预览**：必须满足相同房间、相同版本、授权房主、递增指令序号、合理播放位置和时间边界，才能进行快通道预览。
5. **永远接受 Muse 最终结果**：不能由 P2P 无条件修改房间的 canonical version、聊天历史或服务器 ACK，服务器 STATE 到来时对齐，并消除重复执行。
6. **断线回退**：失去 DataChannel 或失去授权/换房/切换片源后，立即停止快通道应用，继续按现有 Muse 方式处理；不因为快通道失效而中断本地播放。
7. **端到端同一场电影**：双方已 READY，源身份匹配才允许预览 PLAY；字幕和 AI 题目仍由原有控制流处理。
8. **移动系统行为**：iOS 后台 / Android 切后台导致 WebRTC 暂停、换网、锁屏，必须清理旧连接，回前台重新绑定房间。

## 分阶段实施

- **阶段 1（本次）**：iPad / Android `P2PFastPathGate` 授权、去重、版本及有效期校验，两端单元测试，严格禁用正式播放路径。
- **阶段 2**：基于现有独立 Cloudflare 实验环境添加安全的房间级信令，并绑定 Muse 成员身份；实现两个客户端内的原生 WebRTC DataChannel，认证协商后才能打开快速通道。
- **阶段 3**：为 `TestClient` / `MainActivity` 增加仅测试构建可选的 fast-control 调度与回退，保持 Muse AUTH/ACK，双通道统一序号防止重复执行；完成回归测试。
- **阶段 4**：隔离签名 IPA / APK 和两台真机至少 2 小时观影测试，验证真实播放时间差、断线恢复和资源消耗。通过之前**禁止覆盖正式安装包**。

## 第一阶段验收范围

- 允许：验证协议过滤算法的正确性。
- 不允许声称：P2P 播放同步已经上线、APP 已经能自动直连、iPad/Android 构建完成或真实观影时间差已达标。
- 不进行：正式 Muse 服务重启、Cloudflare 正式域名替换、路由器防火墙修改、现有数据库迁移。
