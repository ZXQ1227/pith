# Pith 0.4.1：语音识别授权退出修复

日期：2026-10-24。

## 故障与根因

用户反馈点击权限“开启”后 Pith 退出。读取本机两份对应崩溃记录：

- `Pith-2026-10-24-193122.ips`：19:31:17，版本 0.4.0。
- `Pith-2026-10-24-193204.ips`：19:31:59，版本 0.3.0。

两份均为后台队列 `com.apple.root.default-qos` 上的 `EXC_BREAKPOINT / SIGTRAP`，关键栈一致：

```text
_dispatch_assert_queue_fail
swift_task_isCurrentExecutorWithFlagsImpl
closure #1 in closure #1 in static SystemTranscriber.authorize()
TCCAccessRequest
```

`SystemTranscriber` 具有 `@MainActor` 隔离，原授权回调隐式继承了该隔离。Apple 的 [requestAuthorization 文档](https://developer.apple.com/documentation/speech/sfspeechrecognizer/requestauthorization(_:)) 明确不保证在主队列执行授权回调；[queue 文档](https://developer.apple.com/documentation/speech/sfspeechrecognizer/queue) 也说明识别任务的队列设置不适用于授权回调。SDK 头文件与文档一致，因此默认识别队列为主队列不能解决此问题。

## 修改

- 将无 UI 状态的授权桥接明确标记为 `nonisolated`，授权请求及完成回调采用 `@Sendable`。回调只恢复 continuation，调用方恢复后继续在自身隔离域更新 UI。
- 保留授权状态检查、拒绝提示及取消检查。系统弹窗较晚返回时，已取消的录音不会继续启动。
- 对语音识别结果回调也明确使用 `@Sendable`，仅提取字符串，再显式切回主线程完成状态更新。
- 新增应用层测试目标，用模拟授权状态及后台回调检查该边界，不弹系统权限框，不录音，不调用模型。

生产逻辑只修改 `SystemTranscriber.swift`；另更新测试配置、版本号及验证文档。

## 自动化验证

完整测试：

```text
swift test --scratch-path .build --cache-path .cache --manifest-cache local
Build complete! (7.35s)
✔ Test run with 62 tests in 9 suites passed after 0.032 seconds.
```

新增 5 项测试覆盖后台允许、后台拒绝、已授权不重复请求、已拒绝/受限制不重复请求、取消期间延迟授权。拒绝/受限制用例含两个参数实例。

正式优化模式下的授权专项测试：

```text
swift test --scratch-path .build --cache-path .cache --manifest-cache local -c release --filter SpeechAuthorizationTests
Build complete! (16.04s)
✔ Test run with 5 tests in 1 suite passed after 0.004 seconds.
```

单元测试验证模拟回调线程与状态行为，未单独重现原始 Objective-C 系统调用的隐式隔离陷阱。根因依据是上述两份真实崩溃报告及 SDK 文档；正式应用授权入口另有下述现场验证。

正式构建：

```text
bash build-app.sh /private/tmp/pith-release-0.4.1/Pith.app
Build complete! (17.86s)
Built /private/tmp/pith-release-0.4.1/Pith.app
```

## 安装与现场验证

安装到 `~/Applications/Pith.app`，版本 **0.4.1 (7)**。旧版备份到 `~/Applications/Pith-backups/0.4.0.bGXrno/Pith.app`。Keychain、API 设置、快捷键偏好、词典及历史未由安装脚本改写。

通过桌面工具点击正式应用“语音识别”的“开启”后，设置中的语音识别项变为绿色已授权，按钮变为“管理”。Pith 保持运行，后续核对进程为：

```text
48502 ~/Applications/Pith.app/Contents/MacOS/Pith
```

PID 仅对应本次检查时刻。检查时未发现新增 Pith 崩溃报告；最新两份仍是修复前记录。没有代用户点击系统权限弹窗的允许按钮。随后再次检查，麦克风按钮也已变为“管理”，应用继续保持可用；辅助功能在该检查时刻仍显示待开启。

随后用户按“完成麦克风、辅助功能授权，再用 Fn 录一句话”的验收请求反馈：**“可以正常转成文字”**。据用户实机反馈，0.4.1 的 Fn 听写及语音转文字链路验收通过，本次授权退出问题已闭环。此反馈不扩展为 Fn + 左 Shift 翻译、外接键盘或自动回填的验收结论。

## 归档

`dist/Pith-0.4.1.zip` 通过 `unzip -t`，解包后的包通过严格签名检查。构建、安装、解包三个可执行文件 SHA-256 相同：

```text
a27ae1e4f1b091e10ab438732026053c364a122a7e20e24b8652e3ad13e242d4
```

差异空白检查通过，源码/测试/文档的凭据格式扫描未发现真实 Key。没有提交、推送或发布远端版本。
