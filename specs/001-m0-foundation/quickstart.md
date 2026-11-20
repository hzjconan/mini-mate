# Quickstart: M0 工程基座与能力探测

**Feature**: `001-m0-foundation`

## 前置条件

- Apple Silicon Mac，Xcode 26
- iPhone 16 Pro Max，iOS 26，数据线
- 一个开发者账号（个人付费会员），已在 Xcode > Settings > Accounts 中登录

## 一、首次安装

1. iPhone：设置 > 隐私与安全性 > 开发者模式，打开并重启。
2. Xcode 打开 `App/MiniMate.xcodeproj`，选中 `MiniMate` target > Signing & Capabilities：
   - Team 选择你的开发者团队；
   - Bundle Identifier 保持 `ai.minimate.app.cucumber`（需全局唯一）。
3. 连接 iPhone，选中设备，⌘R 运行。
4. 首次启动提示"不受信任的开发者"时：iPhone 设置 > 通用 > VPN 与设备管理 > 选择你的 Apple ID > 信任。
5. 再次运行，App 显示首页即成功。

## 二、重签（SC-001，目标 ≤ 5 分钟）

付费账号的描述文件约一年有效。到期或验证失败时 App 点开即闪退或提示无法验证。**实测注（2026-11-20）**：付费账号在 iPhone 设置中无"VPN 与设备管理"条目（仅免费/企业证书才显示），吊销证书也不会阻止已安装 App 启动——到期状态暂无法在本机模拟，演练时直接执行下面的 ⌘R 原地重签即可（已验证 ~30 s，数据保留）。

1. 连接 iPhone，打开 Xcode 中的工程。
2. 直接 ⌘R 运行（Xcode 会自动续签描述文件）。
3. App 启动后检查：设置页的密钥状态、以及任何本地数据仍在。
4. 在 `research.md` 的"重签耗时"一栏记录本次耗时。

**不要**删除 App 再重装——那会清空本地数据。

**建议**：在日历里设到期前提醒（付费账号约一年一次；若未来改回免费账号则每周一次）。

## 三、运行能力探测

1. 打开 App > 设置 > 能力探测，点击"开始探测"。
2. 等待所有项完成（< 5 秒）。
3. 点击"导出"，把文本粘贴到 `specs/001-m0-foundation/research.md` 的"实测结果"一节，并逐项写结论。
4. 若 Foundation Models 显示"Apple Intelligence 未开启"：到 设置 > Apple Intelligence 与 Siri 中开启后重新探测，并记录能否开启、是否支持中文。

## 四、Mac 上运行单元测试

```bash
cd Packages/MiniMateKit
swift test
```

## 五、验收清单

- [x] US1：真机安装成功；完成一次重签且数据未丢失；`swift test` 通过
- [x] US2：探测页全部项给出结论；导出报告已写入 `research.md`
- [x] US3：保存假 Key 后重启仍显示"已配置（末 4 位）"；删除后显示"未配置"
- [x] SC-005：`git grep` 检索假 Key 无结果
