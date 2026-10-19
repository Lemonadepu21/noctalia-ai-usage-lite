# AI Usage Lite

Noctalia v5 的轻量 AI 用量插件，显示 **订阅剩余额度、重置时间和 API 余额**。

数据由现有 [ai-usagebar CLI](https://github.com/akitaonrails/ai-usagebar) 查询，插件只负责显示。支持哪些提供商与账户，以 CLI 的实际结果为准。

- 每个状态栏组件绑定一个账户；添加多个组件可同时查看多个账户。
- 展开页使用 Tab，可勾选要显示的账户和用量项。
- 状态栏、Tab 和账户列表使用供应商 Logo；图标随插件离线打包，支持深浅主题。
- 只显示有成功数据的账户；查询暂时失败时保留旧数据并提示状态。
- 支持手动刷新、成功缓存，以及后端提供的重置卡次数和到期时间。

## 快速安装

### 1. 准备 CLI

需要 **Noctalia v5.2.1+（插件 API 32）**、Git，以及已完成账户配置的 **ai-usagebar CLI**。CLI 的安装和登录见[上游说明](https://github.com/akitaonrails/ai-usagebar#readme)。

**还没添加账户？** 先按 [CLI 添加订阅和 API 账户指南](docs/ACCOUNTS.md) 配置。指南包含 Codex、Claude、OpenCode Go、DeepSeek，以及同一服务的多个账户。

已有 Codex 订阅登录时，只需启用对应提供商：

```sh
ai-usagebar settings enable openai
```

先确认至少一个账户能返回成功数据：

```sh
ai-usagebar usage --json
```

运行插件不需要 Python、Node.js 或独立的 Lua 解释器。Arch Linux 通常已有所需的 `flock` 和 `timeout`，分别由 `util-linux` 和 `coreutils` 提供。

### 2. 添加并启用插件

在已运行的 Noctalia 中执行：

```sh
noctalia msg plugins source add ai-usage-lite git https://github.com/Lemonadepu21/noctalia-ai-usage-lite
noctalia msg plugins enable pupu/ai-usage-lite
```

也可通过 **设置 → 插件 → 添加源** 添加上述 Git 仓库，再启用 **AI Usage Lite**。这是 Noctalia 的[原生安装方式](https://docs.noctalia.dev/noctalia/plugins/)，不需要运行安装脚本。

### 3. 添加状态栏组件

进入 **Noctalia 的状态栏编辑器 → 添加组件 → AI Usage Lite**，添加 `bar` 组件。

- **使用 Codex**：默认账户 ID 为 `openai`，有成功数据后即可显示。
- **使用其他账户**：中键点击组件，或从状态栏编辑器打开它的设置，修改“展示账户 ID”。
- **同时显示多个账户**：再添加一个 AI Usage Lite 组件，分别绑定不同账户。

完整组件 ID 为 `pupu/ai-usage-lite:bar`。首次下载和查询可能需要稍等片刻。

**没有 Codex，或组件没有出现？** 默认组件绑定 Codex，无对应数据时会隐藏。先用下面的命令打开展开页，点击右上角“显示设置”，复制目标账户旁的 ID，再到状态栏编辑器修改组件绑定：

```sh
noctalia msg panel-open pupu/ai-usage-lite:panel
```

常见 ID：`openai`（Codex）、`opencode-go`、`deepseek`；命名账户可能是 `openai@work`。以展开页实际列出的 ID 为准。

## 使用与设置

| 操作 | 效果 |
| --- | --- |
| 左键状态栏组件 | 打开或关闭展开页 |
| 右键状态栏组件 | 手动刷新 |
| 点击 Tab / `←` `→` | 切换已选择的账户 |
| 展开页右上角“显示设置” | 勾选 Tab 和各账户的用量项 |
| 展开页刷新按钮 / `R` | 手动刷新 |
| 关闭按钮 / `Escape` | 关闭展开页 |

每个状态栏组件只显示一个账户，最多展示其前两项已选数据。进度条表示**剩余额度**；金额保留后端原值，不自行换算币种或推断预算。

状态栏倒计时按分钟更新；展开页显示本地重置时刻，剩余时间在打开、切换或数据更新时计算。Codex 默认只显示订阅额度和重置卡，附带的 Credits 项默认关闭，可自行选择。

| 设置位置 | 可调整内容 |
| --- | --- |
| 设置 → 插件 → AI Usage Lite 齿轮 | 同步间隔：1–120 分钟，默认 5；查询超时：5–55 秒，默认 30 |
| 中键点击组件 / 状态栏组件设置 | 账户 ID；倒计时开关；进度条宽度：24–100，默认 40 |
| 展开页 → 显示设置 | 一个或多个 Tab，以及各账户的显示项目 |

修改自动生效，无需重启 Noctalia。Tab 和用量项选择会记住；切换界面不会额外查询 CLI。

## 更新、停用与迁移

```sh
# 更新插件源
noctalia msg plugins update ai-usage-lite

# 停用，保留文件和设置
noctalia msg plugins disable pupu/ai-usage-lite
```

如果正在运行旧的 `felipeartur/ai-usagebar` 插件，可先在插件设置中禁用它，再移除旧状态栏组件，避免两个插件同时查询。禁用会保留旧文件和设置，便于回退。

**本地开发版优先于 Git 源。** 如果已存在 `~/.local/share/noctalia/plugins/ai-usage-lite`，添加仓库不会自动替换它。迁移前先备份并移出该本地目录，再重新启用插件；请勿直接删除原目录或缓存。

## 常见问题

**CLI 支持 DeepSeek 吗？**

已核对的 CLI v1.37.0 支持 DeepSeek API Key。先在 CLI 中配置并确认查询成功，插件就能显示；插件不提供登录、保存密钥或开通服务的功能。其他提供商可运行 `ai-usagebar vendors --json` 查看。

**为什么某个账户没有 Tab？**

从未成功取得数据的账户不会显示。先检查 CLI 查询结果，再检查展开页“显示设置”是否关闭了该 Tab。临时失败但已有成功缓存的账户会继续显示旧数据。

**为什么余额没有进度条？**

后端没有提供可用于额度百分比的定义时，只显示金额或文本，避免把余额误当成额度。合法的零余额仍会显示。

**如何排查刷新失败？**

先确认 `ai-usagebar usage --json` 能成功返回数据，再检查插件同步间隔和超时设置。可用以下命令手动刷新：

```sh
noctalia msg plugin pupu/ai-usage-lite:poller all refresh
```

## 开发与许可

已在本机验证真实 CLI 查询、Tab 切换和显示开关；API 余额与多账户使用虚构数据做隔离测试，不能视为所有供应商真实查询均已通过。

[CLI 账户配置](docs/ACCOUNTS.md) · [技术说明与测试方法](docs/DEVELOPMENT.md) · [MIT 许可](LICENSE)

供应商 SVG 来自 [Lobe Icons](https://github.com/lobehub/lobe-icons)（MIT）；来源版本、修改及覆盖范围见 [图标说明](ai-usage-lite/icons/README.md)。
