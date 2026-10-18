# 用 CLI 添加订阅与 API 账户

[返回安装说明](../README.md)

本指南按 **ai-usagebar CLI v1.37.0** 的命令核对。这里是接入你已有的账户，不会购买订阅或给 API 账户充值。插件不负责登录或保存密钥。

## 先确定账户类型

```sh
ai-usagebar vendors
```

该命令列出 CLI 支持的服务及配置状态，不查询网络。需要查看提供商 ID、登录方式和环境变量名称时，使用 `ai-usagebar vendors --json`。

| 账户 | 提供商 ID | 配置方式 |
| --- | --- | --- |
| Codex / ChatGPT 订阅 | `openai` | 复用 Codex CLI 的订阅登录 |
| Claude 订阅 | `anthropic` | 复用 Claude Code 的登录 |
| OpenCode Go 订阅 | `opencode-go` | 配置该订阅的 API Key |
| DeepSeek API 余额 | `deepseek` | 配置 DeepSeek API Key |

`ai-usagebar settings enable <ID>` 只启用指定服务，保留其他配置；它不会替你完成登录或创建 Key。

## Codex / ChatGPT 订阅

已经登录 Codex 的用户可以跳过登录步骤。否则，先安装官方 Codex CLI，然后通过 ChatGPT 账户登录：

```sh
codex login
ai-usagebar settings enable openai
ai-usagebar usage --json
```

目标条目的 ID 为 `openai`，成功时其 `status` 为 `ready`。这是 Codex 订阅额度，不是 OpenAI API 余额；无需为此填写 OpenAI API Key。

## Claude 订阅

先安装 Claude Code，运行 `claude` 并在其界面完成账户登录，然后执行：

```sh
ai-usagebar settings enable anthropic
ai-usagebar usage --json
```

插件中的账户 ID 为 `anthropic`。Claude 订阅和 Anthropic API 是不同类型的账户，不要用 API Key 代替订阅登录。

## OpenCode Go 与 DeepSeek

在对应服务的账户后台取得自己的 Key，然后编辑 CLI 配置：

```text
~/.config/ai-usagebar/config.toml
```

**只添加或修改需要的部分，保留其他账户。** 如果文件中已有同名表，就修改现有字段，不要重复追加相同的 `[表名]`。

### OpenCode Go 订阅

```toml
[opencode-go]
enabled = true
api_key = "REPLACE_WITH_OPENCODE_GO_KEY"
```

将占位符替换为该 Go 订阅可用的 Key。账户 ID 为 `opencode-go`，可展示的额度项目取决于 CLI 实际返回的数据。

### DeepSeek API 余额

```toml
[deepseek]
enabled = true
api_key = "REPLACE_WITH_DEEPSEEK_KEY"
```

将占位符替换为自己的 DeepSeek Key。账户 ID 为 `deepseek`；这是 API 余额，不是订阅额度。真实余额为零时，插件仍会显示零。

### 保存并验证

使用配置文件保存 Key 时，限制文件权限：

```sh
chmod 600 ~/.config/ai-usagebar/config.toml
ai-usagebar usage --json
```

CLI 也支持 `OPENCODE_GO_API_KEY` 和 `DEEPSEEK_API_KEY` 环境变量。注意：在某个终端中临时 `export`，不会把变量传给已经运行的 Noctalia；使用环境变量时，需要让启动 Noctalia 的桌面会话也继承它们。配置文件不依赖这项会话设置。不要把含真实 Key 的配置提交到 Git。

## 同一服务添加多个账户

### 第二个 Codex 账户

```sh
ai-usagebar account add work --codex
ai-usagebar usage --json
```

按命令提示完成独立账户登录。该账户通常以 `openai@work` 出现在结果中；以实际报告的 ID 为准。添加 Claude 命名账户可使用 `ai-usagebar account add work`。

### 第二个 DeepSeek 账户

在已启用的 DeepSeek 配置下增加命名账户：

```toml
[[deepseek.accounts]]
label = "work"
api_key = "REPLACE_WITH_WORK_DEEPSEEK_KEY"
```

随后查询 `ai-usagebar usage --json`，使用其返回的完整账户 ID（例如 `deepseek@work`）。不同 Key 是否共享余额由服务商的计费账户决定，插件不会把它们合并或相加。

## 让新账户显示在 Noctalia

1. 先确认 `ai-usagebar usage --json` 中目标条目的 `status` 为 `ready`。命令退出码为 0，并不代表每个账户都查询成功。
2. 打开 AI Usage Lite，点击右上角“显示设置”，勾选新账户的 Tab 和用量项目；原有选择会保留。
3. 要在状态栏显示该账户，添加一个 AI Usage Lite 组件，在组件设置中填写完整账户 ID。每个组件只绑定一个账户。
4. 右键组件或点击展开页刷新按钮，即可重新查询。

组件暂时隐藏时，可直接打开展开页：

```sh
noctalia msg panel-open pupu/ai-usage-lite:panel
```

查不到数据时，先解决 CLI 返回的配置、认证或网络问题；没有成功数据的账户不会被插件展示。

更多服务、配置路径和版本差异，请以 [ai-usagebar 官方配置说明](https://github.com/akitaonrails/ai-usagebar/blob/main/docs/configuration.md)及[配置示例](https://github.com/akitaonrails/ai-usagebar/blob/main/config.example.toml)为准。本文的 Key 均为占位符；未替用户登录新账户或执行真实 API 余额查询。
