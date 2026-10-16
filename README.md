# AI Usage Lite

一个面向 **Noctalia v5** 的轻量 AI 订阅用量插件，支持 **Codex** 和 **OpenCode Go**。

使用现有 [ai-usagebar CLI](https://github.com/akitaonrails/ai-usagebar) 查询数据。插件只负责刷新、缓存和显示，不实现认证或供应商网络请求。

## 功能

- **紧凑状态栏**：Codex 图标、两行剩余额度进度条和重置倒计时，上行为 5 小时，下行为每周。
- **双订阅展开页**：切换查看 Codex 的 5 小时/每周额度，以及 OpenCode Go 的滚动/每周/月度额度。
- **Codex 重置卡**：显示可用手动重置次数、剩余有效时间和本地到期时刻。仅展示 CLI 提供的信息，不执行重置。
- **单独手动刷新**：状态栏右键、展开页右上角刷新按钮，或按 `R`。
- **失败保留数据**：逐订阅保存上次成功数据，重启后可恢复；旧数据和过期图标仅在展开页显示，详情可悬停查看。
- **界面与查询分离**：切换订阅不查询 CLI；展开页不进行每秒或定时整页渲染。

百分比和进度条都表示 **剩余额度**。重置时刻到达后，插件会等待 CLI 确认，不自行把额度恢复为 100%。

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

CLI 的安装、账户和认证配置见其[上游项目](https://github.com/akitaonrails/ai-usagebar)。本插件目前固定读取默认账户 `openai` 和 `opencode-go`，不支持 `provider@account` 命名账户。

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
| 点击订阅标签 / `←` `→` | 切换 Codex 与 OpenCode Go |
| 展开页刷新按钮 / `R` | 手动刷新用量 |
| 关闭按钮 / `Escape` | 关闭展开页 |

状态栏倒计时按分钟更新；展开页显示本地重置时刻，剩余时间在打开、切换订阅或数据更新时计算。所有日期时间遵循系统本地时区。

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

## 刷新与缓存

- 每 5 分钟调用一次 `ai-usagebar usage --json`，一个进程查询全部配置的订阅。
- 30 秒进程超时，额外 2 秒强制结束宽限；Noctalia 捕获超时为 35 秒。
- 忙碌标志、5 秒最小启动间隔和跨服务重载的文件锁，防止重复并发。
- 15 秒轻量心跳检查；检测到休眠/时间跳变后重新查询，回调失效时允许重试并忽略迟到结果。
- 单个订阅失败时保留该订阅的成功缓存，另一订阅仍可正常更新。
- 缓存使用临时文件加重命名保存，位置由 Noctalia 的 `pluginDataDir()` 管理，更新插件不会覆盖缓存。

缓存只包含整理后的额度、计划名称、数据时间和重置卡信息；不保存认证信息、CLI 原始错误字符串或完整输出。若刷新失败，先检查 CLI 是否能为相应订阅返回正常条目。

## 源码与验证

```text
catalog.toml                 Noctalia 插件源索引
ai-usage-lite/
  plugin.toml                插件声明
  model.luau                 JSON 验证、UTC 时间和缓存整理
  service.luau               单一刷新服务
  bar.luau                   Codex 状态栏
  panel.luau                 双订阅展开页
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

自检覆盖时间解析、部分失败保留缓存、超时与并发保护、服务恢复、400 次模拟切换、固定按钮回调、重置卡次数和到期时间。已在 Arch Linux / Niri / Noctalia v5.2.1 进行真实查询与界面检查；长期运行、真实断网和休眠唤醒仍需要更多使用验证。

## 许可

[MIT](LICENSE)。依赖的 Noctalia 和 ai-usagebar 由各自项目维护。
