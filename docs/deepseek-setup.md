# DeepSeek V4 + macOS 语音识别

版本 0.2.1（2026-10-23）支持将 macOS 系统语音识别与文字模型分开使用：

- 语音识别方式：macOS 系统语音识别。
- 说话语言：普通话（zh-CN），设置中也可选英语、日语和香港粤语。
- Base URL：`https://api.deepseek.com`。
- 文本模型：`deepseek-v4-pro`。
- API Key：在设置中填写新的官方 Key，点击“保存 API 设置”；仅保存在 macOS Keychain。

重新打开 Pith 会显示设置窗口。首次录音需在系统弹窗中授权“麦克风”和“语音识别”。系统支持设备端识别时优先在本机处理，否则可能使用 Apple 在线识别。仅识别后的文字和词典发送到 DeepSeek，音频不会发送到 DeepSeek。文字整理请求使用 `thinking.type=disabled`。

此前提供的 Key 在 DeepSeek 官方 `/models` 接口返回 HTTP 401，未保存为可用凭据。后续截图显示应用使用了错误的占位凭据。2026-10-23 用户重新提供的新 Key 已通过 `/models` 验证（HTTP 200），保存到 Pith 使用的 Keychain 项并读回比对一致；`deepseek-v4-pro` 的真实文本请求返回 HTTP 200 和非空结果。本文档不保存任何密钥。

参考：[官方模型列表](https://api-docs.deepseek.com/api/list-models/)、[Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/)。

自动测试覆盖已有交互、API 转写流程、系统识别后的文字请求不调用音频 API、空识别结果、旧版配置迁移，以及 DeepSeek 禁用思考参数。真实语音识别仍需本机授权和录音验证；真实模型完成请求已在更新 Key 后通过验证。

0.2.1 构建验证输出：`Test run with 35 tests in 6 suites passed after 0.016 seconds.` Release 构建和构建脚本内严格签名校验通过。DeepSeek 和系统识别偏好设置保存后读取一致。最初配置预设时未修改 Keychain，后续凭据修复已保存有效 Key 并读回校验。系统启动命令返回 0；桌面自动化连接仍超时，真实录音尚未完成自动验收。凭据修复未修改产品代码；现有重试逻辑每次都会重新读取 Keychain，可以直接重试原录音。

## 404 排查与安装修复

随后用户录音报 HTTP 404。进程检查发现运行路径实际为 `~/Applications/Pith.app`，其版本为 0.1.1。先前 0.2.1 仅在临时构建目录；`open` 成功未证明实际启动了新版。0.1.1 不支持系统语音识别，仍向 DeepSeek 的音频转写路径发送请求。

已将原安装包备份到 `~/Applications/Pith-backups/`，将已校验的 0.2.1 安装到 `~/Applications/Pith.app`，退出旧进程后启动新版。验证证据：

- 安装包签名：`valid on disk`、`satisfies its Designated Requirement`。
- 运行进程采样：`Identifier: app.pith.desktop`、`Version: 0.2.1 (4)`，主线程正常等待 AppKit 事件。
- 保存的配置：`baseURL=https://api.deepseek.com`、`textModel=deepseek-v4-pro`、`transcriptionSource=system`、`speechLocale=zh-CN`。
- 未修改密钥或历史数据；应用重启后原会话的录音重试状态不再保留，需要新录音验证。

后续升级必须核对真实运行路径和进程版本，不能仅凭 `open` 退出码判断升级成功。实际录音验证需用户完成系统权限授权和一次短句输入。

人工回归结果（2026-10-23）：新版启动后，用户重新录音并确认“已能正常转成文字”。本次 404 故障已修复；这是用户实机验收结果，不是自动化录音测试。
