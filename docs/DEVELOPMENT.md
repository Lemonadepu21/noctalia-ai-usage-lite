# 开发与技术说明

[返回安装和使用说明](../README.md)

## 刷新与缓存

- 默认每 5 分钟调用一次 `ai-usagebar usage --json`，可在设置中修改，一个进程查询全部配置的订阅。
- 默认 30 秒进程超时，额外 2 秒强制结束宽限；Noctalia 捕获超时比配置值多 5 秒，最多 60 秒。
- 忙碌标志、5 秒最小启动间隔和跨服务重载的文件锁，防止重复并发。
- 15 秒轻量心跳检查；检测到休眠/时间跳变后重新查询，回调失效时允许重试并忽略迟到结果。
- 单个账户失败时保留该账户的成功缓存，其他账户仍可正常更新；配置中已移除的账户不会留在选择器中。
- 缓存使用临时文件加重命名保存，位置由 Noctalia 的 `pluginDataDir()` 管理，更新插件不会覆盖缓存。

缓存只包含整理后的展示字段、计划名称、数据时间、重置卡信息和 Tab/显示项目选择；v0.4.0 会读取旧版缓存，并在下一次成功保存时写入新版格式。不保存认证信息、CLI 原始错误字符串或完整输出。若刷新失败，先检查 CLI 是否能为相应订阅返回正常条目。

## 支持范围

CLI schema v1 的 `sections` 是展示依据：`metric`、`text`、`block` 均支持，`spacer` 由界面间距替代；旧的仅含 `metrics` 的报告也可读取。新提供商只要使用同一报告结构，无需逐个修改插件。DeepSeek 已由 CLI 的 API Key 提供商支持，须先在 CLI 配置并成功查询；插件不代为配置密钥。Codex 条目中的附加 Credits 并不代表已配置独立的 OpenAI API 账户。

未来未知的 section 类型会忽略；若没有可展示字段，会保留旧成功数据并报告不可用。

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

自检覆盖未知提供商、多账户、金额与纯文本余额、可用数据过滤、Tab/显示项目选择、组件独立账户、旧缓存迁移、时间解析、部分失败保留缓存、可配置同步间隔和超时、查询中修改设置、并发保护、服务恢复、400 次模拟切换、固定按钮回调、状态栏设置、重置卡次数和到期时间。v0.2.2 已在 Arch Linux / Niri / Noctalia v5.2.1 进行真实查询与界面检查；v0.3.0 新增原生设置，v0.4.1 扩展为通用展示层并恢复可选 Tab；余额和命名账户使用虚构数据测试，长期运行、真实断网和休眠唤醒仍需要更多使用验证。
