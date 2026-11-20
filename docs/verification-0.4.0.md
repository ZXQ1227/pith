# Pith 0.4.0 验证记录

日期：2026-10-24。

## 自动化测试与构建

执行：`swift test --scratch-path .build --cache-path .cache --manifest-cache local`。

```text
Build complete! (6.11s)
✔ Test run with 57 tests in 8 suites passed after 0.020 seconds.
```

在原有 46 项基础上新增 11 项，覆盖 Fn 单次触发、左 Shift 的两种按下顺序和先松开、其他修饰键/普通键屏蔽、先按住普通键再按 Fn、没有物理 Fn 边沿的事件、监听中断重置、多个触发键的归属、Fn 结束翻译或按住录音、自定义组合校验/序列化和旧预设兼容。状态机测试不代表 macOS 实体键盘已验收。

执行：`bash build-app.sh /private/tmp/pith-release-0.4.0/Pith.app`。

```text
Build complete! (18.13s)
Built /private/tmp/pith-release-0.4.0/Pith.app
```

正式包经过 ad-hoc 签名及严格签名验证。源码差异检查未发现空白错误，`Sources`、`Tests`、`docs` 的凭据格式扫描未发现真实 Key。没有新增外部依赖。

开发中修正了 Swift 6 对主线程回调返回 CGEvent 的隔离限制，以及可观察模型初始化的顺序问题。隔离 QA 副本最初缺少 Tests 目录导致 Swift Package 判断源文件重叠，补齐后成功构建；该问题不影响正式项目。

## 原生界面验证

使用本轮源码的临时副本 `/private/tmp/pith-ui-0.4.0-qa`，独立 bundle ID `app.pith.uiqa04`、临时数据目录和占位凭据。音频、系统转写和 API 均使用模拟实现；没有真实录音或模型请求，没有访问真实 Key、词典或历史。录音条验证使用仅存在于测试副本中的模拟翻译入口，并让测试录音条取得焦点以供桌面工具操作。正式包不包含这些替换或入口。测试应用已退出。

通过桌面工具操作确认：

- Fn 主快捷键、Fn + 左 Shift 翻译、备用组合键及权限提示正确展示。
- 普通字符不能保存为快捷键，错误提示可见。
- 录入 Control + Option + D，保存成功，并在重启后保留。
- 在录入弹窗再次输入已有组合键，不会开始录音；保存时明确拒绝重复组合。
- Esc 关闭录入弹窗。
- 模拟翻译录音条显示“语音翻译”、计时、音量、结束/取消按钮及语言选择。
- 录音中从简体中文切换到 English，点击结束，编辑器中本次处理方式为翻译、目标为 English，并显示模拟英文结果，证明选择进入本次处理请求。
- 检查快捷键设置、录入弹窗和录音条截图，没有文字遮挡或按钮溢出。

自动化工具发送的组合键没有触发 Carbon 全局回调；重启测试应用后仍如此。未据此宣称全局键已通过，也未添加非独占的事件监听来掩盖问题。需要实体键盘验收，区分系统事件投递限制和真实设备兼容性。Fn 的硬件行为同样待授权后验证。

## 安装和归档

安装输出：

```text
Installed: ~/Applications/Pith.app
Backup: ~/Applications/Pith-backups/0.3.0.jNUF0l/Pith.app
0.4.0
6
```

重启后观测到进程 `47223 ~/Applications/Pith.app/Contents/MacOS/Pith`（PID 仅对应本次检查时刻）。正式设置显示主快捷键 Fn、两种备用组合、DeepSeek 官方地址、`deepseek-v4-pro`、macOS 系统转写、Key 已保存、历史开启。没有改写 API Key。

归档：`dist/Pith-0.4.0.zip`，`unzip -t` 返回 `No errors detected`。另解包至临时目录，严格签名验证通过。构建、安装、解包三个可执行文件 SHA-256 相同：

```text
5d2dc78c23b771fc983220271f23884d7e84d8a4bfbc8cbe3cb1f514ba1ebef0
```

## 待用户实机验收

正式设置当前显示辅助功能、麦克风、语音识别需要授权。已请用户自行允许后测试 Fn 开始/结束、Fn + 左 Shift 翻译及备用组合键。由于本地 ad-hoc 签名升级可能重置系统对应用的权限识别，需要再次允许。没有自动更改系统权限。

本轮真实语音识别、实体 Fn/外接键盘、系统 Fn 组合兼容性和跨应用自动回填尚未验收。没有提交或推送 Git，也没有发布商业化功能。
