# Pith 0.5.1：Fn 长按提示与语音胶囊

日期：2026-10-26。版本：0.5.1 (10)。依据用户提供的三个 Typeless 参考截图实现。

## 交互

- 空闲时，单独按住 Fn 达到 600 毫秒，显示非激活的快捷键提示。松开关闭并释放提示窗口，不启动录音。短按 Fn 继续开始／结束录音。
- 提示显示期间加入左 Shift 或 Space，隐藏提示并在 Fn 松开时触发翻译或问答。普通按键、其他修饰键、休眠、监听中断、停止监听都会清理提示或待显示任务。
- 录音过程中不显示长按提示，长按 Fn 后松开仍可以结束当前录音。
- 录音胶囊为 232 × 68 pt：左侧取消、中央白色实时波形、右侧完成。波形幅度来自麦克风音量，静音显示平直点线，不假造录音活动。模式通过辅助功能标签及鼠标提示提供。
- 结束录音后，原有非激活面板在相同底部位置切换为 188 × 68 pt 的 Thinking 胶囊，覆盖识别、模型处理和回填阶段。灰色区域为等待动画，不表示完成百分比；系统开启减少动态效果时保持静态。Esc 仍可取消。
- 翻译录音胶囊的右键菜单可更改目标语言，设置页保留目标语言选项。用户现有 English 偏好未改动。
- 成功回填后的隐藏行为、问答结果卡片、错误与复制恢复界面保留。

## 影响范围

`FunctionKeyGesture` 识别长按提示状态；`FunctionKeyMonitor` 管理计时与清理；`HotkeyController` 和 `PithAppModel` 传递提示事件及空闲条件；`PithAppDelegate` 管理提示窗口生命周期和胶囊尺寸；`InteractionViews` 实现三种视觉状态。

没有修改模型提示词、API 请求、语音识别服务、Keychain、词典或历史。

## 测试

执行：`swift test --scratch-path .build --cache-path .cache --manifest-cache local`。

```text
✔ Test run with 80 tests in 14 suites passed after 0.639 seconds.
```

新增 6 项测试覆盖长按显示与释放、长按后选择翻译／问答、普通键打断、快捷键计时取消、录音期间禁止显示提示、中断清理。测试只在进程内构造事件，不向系统发送按键、不录音。

第一次新增测试编译暴露 Swift Testing 对直接传入 mutating Bool 调用的宏展开限制，改为显式比较 `== true/false` 后，上述完整回归通过。日志为 `/private/tmp/pith-tests-0.5.1.log`。

## 视觉检查

通过独立临时工程使用正式 SwiftUI 组件及固定音量，使用 ImageRenderer 生成预览；不实例化生产模型、不读取真实 Key 或历史、不调用 API。检查提示表格、波形收音态／静音态、Thinking、透明边缘与文字排版。

- [长按提示](../dist/verification-0.5.1/hold-hint.png)
- [录音胶囊](../dist/verification-0.5.1/recording.png)
- [静音](../dist/verification-0.5.1/silence.png)
- [Thinking](../dist/verification-0.5.1/thinking.png)

预览工程位于 `/private/tmp/pith-preview-0.5.1/`。离屏图像和单元测试不能代替实体 Fn、麦克风及目标应用的实机体验验收。

## 构建与安装

```text
bash build-app.sh /private/tmp/pith-release-0.5.1/Pith.app
Build complete! (14.37s)
Built /private/tmp/pith-release-0.5.1/Pith.app
```

构建和安装副本都通过 `codesign --verify --deep --strict`，安装路径为 `~/Applications/Pith.app`。读取版本得到 `0.5.1`、`10`，两个可执行文件 SHA-256 一致：

```text
6dbdb12f906950c93a2bd9e5c08fa9a89aaa92f2775b6ac9908285820ad18710
```

旧版安装前压缩备份为 `/private/tmp/Pith-0.5.0-before-0.5.1.zip`，避免新增可被误启动的旧 `.app` 副本。备份及 `dist/Pith-0.5.1.zip` 均通过 `unzip -tq`。

## 实机状态与待验收

新版已启动，设置中确认 Key 仍保存、翻译目标为 English、系统语音识别为普通话、自动回填开启。更新后，当前实例的麦克风、语音识别与辅助功能均显示未授权，Fn 提示未启用；需要用户在 macOS 重新恢复权限。未代用户更改安全权限，也未恢复其已删除的备用组合键。

现场 Typeless 也正在运行，验收时请暂时退出以隔离共享 Fn 的干扰。随后用户实机反馈“提示出现，松开消失”，长按提示显示与释放隐藏已通过用户验收。用户未逐项报告三项权限的恢复状态；不由提示可用推定麦克风、语音识别均已恢复。真实录音 → Thinking → 回填收起仍待用户实机确认，本记录不宣称已经通过。
