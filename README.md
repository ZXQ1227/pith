# Pith · Mac AI 语音输入与实时回填

**按一下 Fn 开始说，再按一下，把整理好的文字填回你正在写的地方。**

Pith 是一款开源的 macOS 菜单栏语音输入工具。用它口述邮件、聊天消息和笔记，把说出口的话整理成可直接使用的文字。你也可以说中文、直接输入英文，或者选中一段文字，用语音告诉 AI 怎么改。

**[从源码安装 Pith](#install)** · [DeepSeek 配置指南](docs/deepseek-setup.md) · [GitHub Releases](https://github.com/ZXQ1227/pith/releases)

macOS 14+ · MIT 许可证 · 自带模型 API Key

**English summary** — Pith is an open-source AI dictation app for the macOS menu bar. It turns speech into polished text, translates spoken input into eight target languages, and lets you rewrite selected text with spoken instructions. Pith supports macOS Speech Recognition or an OpenAI-compatible transcription API, with a configurable OpenAI-compatible text model for editing, translation, and Q&A.

## 一个快捷键，三种用法

| 你想做什么 | 怎么用 | Pith 会做什么 |
| --- | --- | --- |
| **口述一条能直接发的消息** | 短按 `Fn / 🌐` | 转写并整理口述内容，符合回填条件时直接填回原输入框。可选自然、简洁、正式、随意或条列风格。 |
| **用中文说，直接写英文** | `Fn + 左 Shift` | 把口述内容翻译成目标语言，再填回输入框。 |
| **用一句话改好这段文字** | 先选中文字，再按 `Fn + 空格` | 说「把这段缩短一点，保留日期」，Pith 可在原位置替换选中的文字。也可以对选中内容提问，在浮动卡片里看答案。 |

开始录音后，再按 `Fn` 完成，或按 `Esc` 取消。空闲时长按 `Fn` 可以查看快捷键提示。设置里也可以给外接键盘配置组合键，组合键支持按住说话。

### 第一次试用，说这句话

在备忘录里点一下输入框，按 `Fn`，说「明天的会改到下午三点，麻烦大家提前看一下议程」，再按 `Fn`。Pith 会把这句话整理成可直接发送的消息。把翻译目标设为英语，再用 `Fn + 左 Shift` 说一遍，就能在原输入框得到英文版本。

## 适合每天使用的细节

- **说完接着写。** Pith 在录音开始时记录目标输入框，完成时检查焦点和选区。无法安全回填时会保留结果，你仍然可以复制。
- **让人名和术语有据可循。** 把客户名、项目名和行业术语加进个人词典。词条可用于文字整理，识别阶段是否支持词典提示取决于所选转写方式和服务。
- **一句话可以反复打磨。** 查看原始转写、手动改字、换风格或生成译文。文字整理失败时，已识别的原文会保留，可直接重试文字处理。
- **用自己的模型服务。** 可用 macOS 系统语音识别配合 DeepSeek 整理文字，也可选择支持 OpenAI 兼容接口的服务来转写和处理文本。

<a id="install"></a>

## 下载与安装

当前版本可从源码构建，GitHub Releases 暂无预编译安装包。

**需要** macOS 14 或更新版本、带 Swift 6 的 Xcode Command Line Tools，以及支持 OpenAI 兼容 Chat Completions 接口的模型配置。

```sh
git clone https://github.com/ZXQ1227/pith.git
cd pith
bash build-app.sh /private/tmp/pith-release/Pith.app
open /private/tmp/pith-release/Pith.app
```

1. 在菜单栏打开 **Pith → 设置…**，选择语音识别方式，填写 API Base URL、文本模型和 API Key。
2. 按 macOS 提示授予麦克风权限。使用系统转写时还需允许语音识别。使用 `Fn` 快捷键、选区读取和自动回填时，需允许辅助功能权限。
3. 把光标放进一个输入框，短按 `Fn` 说一句话，再按 `Fn` 完成。

已有 DeepSeek API Key？可以从 **macOS 系统语音识别 + DeepSeek 文本整理** 开始。 [查看 DeepSeek 配置指南](docs/deepseek-setup.md)

## 常见问题

### Pith 和 Mac 自带听写有什么区别？

Pith 在语音转写后增加了 AI 文字整理、口述翻译和选中文字改写。普通听写会把你说出的提问或请求保留为文字。想让模型回答问题、起草内容或执行改写，可以使用 `Fn + 空格` 的 Ask Anything 模式。

### Pith 支持哪些翻译目标语言？

简体中文、繁体中文、英语、日语、韩语、法语、德语和西班牙语。你可以在设置里切换目标语言，实际译文质量取决于配置的文本模型。

### Pith 支持哪些模型接口？

文本整理、翻译和问答使用 OpenAI 兼容的 `POST /chat/completions`。选择 API 转写时，还需要转写服务支持 `POST /audio/transcriptions`。选择 macOS 系统语音识别时，文本服务只需提供 Chat Completions 接口。API Key 保存在 macOS 钥匙串。

### 音频和文字会发到哪里？

- **系统语音识别**由 macOS 处理音频。系统支持时优先在设备上识别，否则可能使用 Apple 在线识别。转写文字、任务指令和个人词典会发给你配置的文本服务。
- **API 转写**会将音频发给你配置的转写服务。识别后的文字、任务指令和个人词典会发给你配置的文本服务。
- **Ask Anything** 只在你主动触发时读取所选文字，并把选区和口述指令一同交给模型。普通听写和翻译只处理本次口述。
- **本地历史**默认关闭。开启后在本机以明文保存最近 100 条文字记录，历史记录不会随请求发给模型。

## 项目文档

- [快捷键行为与权限](docs/shortcuts-0.4.0.md)
- [文字编辑、词典与历史](docs/value-features-0.3.0.md)
- [0.5.1 构建与验证记录](docs/verification-0.5.1.md)
- [反馈问题](https://github.com/ZXQ1227/pith/issues)
- [MIT 许可证](LICENSE)
