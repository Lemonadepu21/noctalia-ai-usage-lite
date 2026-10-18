# AI Usage Lite

一个面向 **Noctalia v5** 的轻量 AI 用量插件，显示 ai-usagebar CLI 返回的**订阅额度、API 余额和多账户数据**。

使用现有 [ai-usagebar CLI](https://github.com/akitaonrails/ai-usagebar) 查询数据。插件只负责刷新、缓存和显示，不实现认证或供应商网络请求。

## 功能

- **可选状态栏账户**：展开页选择任意账户后点击图钉；显示前两项数据，百分比额度使用紧凑进度条，金额或文本按后端原值显示。默认保留 Codex 优先。
- **通用展开页**：根据 CLI 返回的账户动态生成选择器，支持订阅、API 余额、同一提供商的多个命名账户和后端支持的自定义提供商。
- **重置卡**：后端提供结构化重置次数和到期信息时，显示剩余次数、有效时间和本地到期时刻；不执行重置。
- **单独手动刷新**：状态栏右键、展开页右上角刷新按钮，或按 `R`。
- **失败保留数据**：逐订阅保存上次成功数据，重启后可恢复；旧数据和过期图标仅在展开页显示，详情可悬停查看。
- **界面与查询分离**：切换账户或固定状态栏账户不查询 CLI；展开页不进行每秒或定时整页渲染。
- **原生设置**：直接在 Noctalia 中调整同步间隔、查询超时、状态栏倒计时和进度条宽度。

后端将指标声明为 `headline="percent"` 时，百分比和进度条表示 **剩余额度**；`headline="value"`、文本或说明块中的金额和数值按原值显示，不猜币种、汇率或预算。重置时刻到达后，插件会等待 CLI 确认，不自行把额度恢复为 100%。

## 环境要求

| 项目 | 要求 |
| --- | --- |
| Noctalia | v5.2+，插件 API 32；已在 v5.2.1 测试 |
| ai-usagebar | 已安装并完成订阅配置，JSON schema v1；已在 v1.37.0 测试 |
| Git | 由 Noctalia 下载插件源 |
| `flock` / `timeout` | Arch 的 `util-linux` / `coreutils` 提供 |

运行时不需要 Python、Node.js、Lua 命令行解释器或单独的后台守护程序。Noctalia 自带 Luau 运行环境。

先确认 CLI 能正常查询你的订阅：

```sh
ai-usagebar usage --json
```

CLI 的安装、账户和认证配置见其[上游项目](https://github.com/akitaonrails/ai-usagebar)。插件读取 `ai-usagebar usage --json` 的全部账户，保留完整账户 ID（如 `openai@work`），不维护提供商白名单。可用提供商、认证、账户和启用状态由 CLI 管理，可运行 `ai-usagebar vendors --json` 查看本机后端目录。插件仅展示 CLI 已返回的数据，不会自动启用提供商或读取密钥。

## 快速安装

在已运行的 Noctalia 中执行：

```sh
noctalia msg plugins source add ai-usage-lite git https://github.com/Lemonadepu21/noctalia-ai-usage-lite
noctalia msg plugins enable pupu/ai-usage-lite
```

下载完成后，进入 **设置 → 状态栏 → 添加组件**，添加 **AI Usage Lite** 的 `bar` 组件即可。组件完整 ID 为 `pupu/ai-usage-lite:bar`。

也可以在 **设置 → 插件 → 添加源** 中选择 Git，填入上面的仓库地址，再启用 AI Usage Lite。这使用 Noctalia 的[官方插件源机制](https://docs.noctalia.dev/noctalia/plugins/)，不需要运行额外安装脚本。

首次下载可能需要稍等片刻。启用插件会启动刷新服务；添加状态栏组件后才会看到图标。

### 从原 AI Usage 插件迁移

如果正在使用 `felipeartur/ai-usagebar`，先禁用它，避免两个轮询服务同时查询：

```sh
noctalia msg plugins disable felipeartur/ai-usagebar
```

在状态栏编辑器中移除旧组件，再添加新组件。禁用操作保留旧插件及其设置，便于回退。

### 已装本地开发版

`~/.local/share/noctalia/plugins/ai-usage-lite` 中的本地版本优先于 Git 源。可以继续使用本地版本；若要迁移到仓库更新，请先备份并移出这个本地目录，再重新加载 Noctalia。安装命令不会替你覆盖或删除该目录。

## 使用

| 操作 | 效果 |
| --- | --- |
| 左键状态栏组件 | 打开/关闭展开页 |
| 右键状态栏组件 | 手动刷新用量 |
| 账户下拉列表 / `←` `→` | 切换查看 CLI 返回的账户 |
| 账户旁的图钉按钮 | 固定该账户到状态栏，并记住选择 |
| 展开页刷新按钮 / `R` | 手动刷新用量 |
| 关闭按钮 / `Escape` | 关闭展开页 |

状态栏倒计时按分钟更新；展开页显示本地重置时刻，剩余时间在打开、切换账户或数据更新时计算。所有日期时间遵循系统本地时区。

图钉选择存储在插件数据目录，重启后恢复。账户从 CLI 报告中移除后，界面自动回退到其他可用账户；CLI 返回的错误账户仍可选择查看状态。

手动重置次数为 `0` 时会显示 0 次；CLI 没有提供次数或到期时间时不推断。若有多个不同的重置卡到期时刻，会分别显示。

常用命令：

```sh
# 打开展开页
noctalia msg panel-open pupu/ai-usage-lite:panel

# 手动刷新
noctalia msg plugin pupu/ai-usage-lite:poller all refresh

# 更新插件源
noctalia msg plugins update ai-usage-lite

# 停用插件，保留文件和设置
noctalia msg plugins disable pupu/ai-usage-lite
```

自动更新是否启用，遵循 Noctalia 的插件更新设置。

## 在 Noctalia 中配置

**设置 → 插件 → AI Usage Lite 右侧齿轮**：

| 设置 | 默认值 | 范围 |
| --- | --- | --- |
| 同步间隔 | 5 分钟 | 1–120 分钟 |
| 查询超时 | 30 秒 | 5–55 秒 |

**中键点击状态栏组件**，或进入状态栏编辑器打开该组件设置：

| 设置 | 默认值 | 范围 |
| --- | --- | --- |
| 显示重置倒计时 | 开启 | 开启/关闭 |
| 进度条宽度 | 40 | 24–100 逻辑像素 |

修改后自动生效，无需重启 Noctalia。同步间隔从上一次查询开始时刻重新计算；查询超时从下一次查询生效，不中断当前请求。修改配置不会清空成功缓存，也不会产生重复并发查询。超过两个同步周期的数据才按旧数据标记，查询失败或缓存恢复除外。

验收：将间隔改为 1 分钟，观察展开页底部同步时刻更新；关闭倒计时后状态栏保留图标、进度条和百分比，展开页仍显示重置时刻；调整宽度后立即观察变化。最后按自己的偏好设置，右键刷新并来回切换账户，确认按钮仍响应。

## 刷新与缓存

- 默认每 5 分钟调用一次 `ai-usagebar usage --json`，可在设置中修改，一个进程查询全部配置的订阅。
- 默认 30 秒进程超时，额外 2 秒强制结束宽限；Noctalia 捕获超时比配置值多 5 秒，最多 60 秒。
- 忙碌标志、5 秒最小启动间隔和跨服务重载的文件锁，防止重复并发。
- 15 秒轻量心跳检查；检测到休眠/时间跳变后重新查询，回调失效时允许重试并忽略迟到结果。
- 单个账户失败时保留该账户的成功缓存，其他账户仍可正常更新；配置中已移除的账户不会留在选择器中。
- 缓存使用临时文件加重命名保存，位置由 Noctalia 的 `pluginDataDir()` 管理，更新插件不会覆盖缓存。

缓存只包含整理后的展示字段、计划名称、数据时间、重置卡信息和状态栏选择；v0.4.0 会读取旧版缓存，并在下一次成功保存时写入新版格式。不保存认证信息、CLI 原始错误字符串或完整输出。若刷新失败，先检查 CLI 是否能为相应订阅返回正常条目。

## 支持范围

CLI schema v1 的 `sections` 是展示依据：`metric`、`text`、`block` 均支持，`spacer` 由界面间距替代；旧的仅含 `metrics` 的报告也可读取。新提供商只要使用同一报告结构，无需逐个修改插件。未来未知的 section 类型会忽略；若没有可展示字段，会保留旧成功数据并报告不可用。

同一周期仍只运行一次 CLI，新增账户不会增加前端查询进程数。后端本身需要查询多少供应商、是否命中缓存以及是否触发限流，遵循 ai-usagebar 的实现。

## 源码与验证

```text
catalog.toml                 Noctalia 插件源索引
ai-usage-lite/
  plugin.toml                插件声明
  model.luau                 JSON 验证、UTC 时间和缓存整理
  service.luau               单一刷新服务
  bar.luau                   通用账户状态栏
  panel.luau                 动态账户展开页
  translations/              原生设置的中英文文案
  tests/                     隔离自检
```

开发检查需要本机的 `lua` 和 `python`，与插件运行时无关：

```sh
cd ai-usage-lite
noctalia plugins lint .
lua tests/test.lua
TZ=America/New_York lua tests/test.lua
python tests/test_process.py
```

自检覆盖未知提供商、多账户、金额与纯文本余额、动态选择器、状态栏固定、旧缓存迁移、时间解析、部分失败保留缓存、可配置同步间隔和超时、查询中修改设置、并发保护、服务恢复、400 次模拟切换、固定按钮回调、状态栏设置、重置卡次数和到期时间。v0.2.2 已在 Arch Linux / Niri / Noctalia v5.2.1 进行真实查询与界面检查；v0.3.0 新增原生设置，v0.4.0 扩展为通用展示层；余额和命名账户使用虚构数据测试，长期运行、真实断网和休眠唤醒仍需要更多使用验证。

## 许可

[MIT](LICENSE)。依赖的 Noctalia 和 ai-usagebar 由各自项目维护。
