# Pith 0.2.0 验证记录

日期：2026-10-23。

## 自动测试

命令：`swift test --scratch-path .build --cache-path .cache --manifest-cache local`

真实输出：

```text
Build complete! (2.16s)
Test run with 31 tests in 6 suites passed after 0.021 seconds.
```

原版基线为 20 项测试。本轮增加 11 项测试，覆盖个人词典校验与容量、8 个翻译目标、历史默认关闭/容量/搜索/重试更新、落盘与重载、文件权限、损坏文件保留，以及使用 URLProtocol 模拟的请求参数、转写失败、整理失败、空结果和取消传播。未使用真实 API 或用户音频。

## Release 与签名

命令：`bash build-app.sh /private/tmp/pith-release/Pith.app`

校验命令：

```sh
codesign --verify --deep --strict --verbose=2 /private/tmp/pith-release/Pith.app
plutil -lint /private/tmp/pith-release/Pith.app/Contents/Info.plist
```

真实输出：

```text
Built /private/tmp/pith-release/Pith.app
/private/tmp/pith-release/Pith.app: valid on disk
/private/tmp/pith-release/Pith.app: satisfies its Designated Requirement
/private/tmp/pith-release/Pith.app/Contents/Info.plist: OK
```

Documents 下的生成包在清除 FinderInfo 后又出现该属性，同时带有 File Provider 标记；两次签名均因 forbidden metadata 失败。改用独立临时目录后通过。构建脚本支持显式输出路径，且在签名后立即校验；`dist/Pith-0.2.0.zip` 来自通过校验的应用包。失败包已移入 `.build/failed-signing/`，避免误用。

ZIP 完整性检查返回 `No errors detected in compressed data`；解压到新的临时目录后，严格签名校验再次返回 `valid on disk` 和 `satisfies its Designated Requirement`。

## 启动与验证边界

`open /private/tmp/pith-release/Pith.app` 返回退出码 0，进程检查确认运行的是该路径下的可执行文件。桌面自动化连接 Pith 持续返回 `timeoutReached`，因此不能将进程运行等同于菜单栏、词典/历史窗口、麦克风录音或跨应用回填验收通过。

待人工验证：菜单栏打开词典与历史、翻译语言选择、真实 API 的词典提示兼容性及输出质量、实际录音、辅助功能权限、跨应用回填。本轮未安装或覆盖旧应用，也未修改真实历史、词典、API Key 或系统权限设置。
