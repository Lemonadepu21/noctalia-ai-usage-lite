# AI Usage Lite

Noctalia v5 的通用 AI 订阅额度与 API 余额插件，由现有 ai-usagebar CLI 查询数据。

- 只显示 CLI 有成功数据的提供商和命名账户，不限制 Codex 或 OpenCode Go。
- 每个状态栏组件绑定一个账户；添加多个 Noctalia 组件可同时显示多个账户。
- 展开页保留 Tab，可勾选一个或多个账户及用量项；Codex 默认只显示订阅额度和重置卡。
- 状态栏、Tab 和账户列表展示本地供应商 Logo，适配深浅主题；未知品牌保留通用图标。
- 单一查询服务、超时、防并发、上次成功数据缓存；只读展示，不实现认证和供应商请求。
- Noctalia 插件齿轮：同步间隔、查询超时；组件设置：账户 ID、倒计时开关、进度条宽度。

插件 ID：`pupu/ai-usage-lite`；状态栏组件：`pupu/ai-usage-lite:bar`。

[快速安装、使用与开发说明](https://github.com/Lemonadepu21/noctalia-ai-usage-lite#readme)
