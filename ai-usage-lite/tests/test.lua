-- Run from the plugin directory: lua tests/test.lua
local source = "./"
local clock = 1792150000
local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}; for k, item in pairs(v) do out[k] = copy(item) end; return out
end
local model = dofile(source .. "model.luau")
assert(model.epoch("1970-01-01T00:00:00Z") == 0)
assert(model.epoch("2026-10-16T11:58:43Z") == 1792151923)
assert(model.epoch("2026-10-16T19:58:43.123+08:00") == 1792151923)
assert(model.epoch("2024-02-29T00:00:00Z") == 1709164800)
for _, value in ipairs({ "2026-02-29T00:00:00Z", "2026-13-01T00:00:00Z", "2026-10-16T24:00:00Z", "bad", "2026-10-16T12:00:00" }) do
    assert(model.epoch(value) == nil, value)
end
assert(model.duration(clock + 1, clock) == "1分")
assert(model.duration(clock, clock):find("待查询"))
assert(model.duration(nil, clock) == "重置时间未知")
local function raw(id, metrics)
    return { id = id, display_name = id == "openai" and "Codex" or id == "opencode-go" and "OpenCode Go" or id, status = "ready", plan = "Plan", fetched_at = "2026-10-16T10:58:21Z", metrics = metrics }
end
local rolling = { label = "Rolling (5h)", percent = 46, reset_at = "2026-10-16T11:58:43Z", window_secs = 18000 }
local weekly = { label = "Weekly", percent = 27, reset_at = "2026-10-22T06:15:12Z", window_secs = 604800 }
local monthly = { label = "Monthly", percent = 25, reset_at = "2026-11-07T01:38:56Z" }
local report = { schema_version = 1, entries = { raw("openai", { rolling, weekly }), raw("opencode-go", { rolling, weekly, monthly }) } }
local expiry = "2026-11-06T22:35:47.975080Z"
report.entries[1].reset_credits = { available = 1, credits = { { expires_at = expiry } } }
local merged = model.merge(nil, report, clock)
assert(#merged.providers.openai.metrics == 2 and #merged.providers["opencode-go"].metrics == 3)
assert(merged.providers.openai.manualResets == 1)
assert(merged.providers.openai.manualExpiries[1] == model.epoch(expiry))
local multiple = copy(report.entries[1])
multiple.reset_credits.credits = { {expires_at=expiry}, {expires_at=expiry}, {expires_at="bad"}, {expires_at="2026-12-01T00:00:00Z"} }
assert(#model.entry(multiple, clock).manualExpiries == 2)
local zero = copy(report.entries[1]); zero.reset_credits.available = 0
assert(model.entry(zero, clock).manualResets == 0)
for _, invalid in ipairs({ -1, 1.5, "1", math.huge }) do
    local invalidEntry = copy(zero); invalidEntry.reset_credits.available = invalid
    assert(model.entry(invalidEntry, clock).manualResets == nil)
end
local absent = copy(zero); absent.reset_credits = nil
assert(model.entry(absent, clock).manualResets == nil)
local partial = copy(report); partial.entries[1] = { id = "openai", status = "error", error = "private diagnostic" }
local kept = model.merge(merged, partial, clock)
assert(kept.providers.openai.metrics[1].percent == 46 and kept.errors.openai)
assert(kept.providers.openai.manualResets == 1)
assert(not kept.errors["opencode-go"])
assert(model.merge(merged, { schema_version = 2, entries = {} }, clock) == nil)
local badMetric = copy(report); badMetric.entries[1].metrics = { { percent = 0/0 }, { percent = -1 }, { percent = "27" } }
assert(model.merge(merged, badMetric, clock).errors.openai)
local restored = model.restore({ version = 1, providers = merged.providers })
assert(restored.openai.stale and restored.openai.metrics[1].percent == 46)
assert(restored.openai.manualResets == 1)
assert(restored.openai.manualExpiries[1] == model.epoch(expiry))
local invalidCache = copy(merged.providers); invalidCache.openai.manualExpiries = { "bad", math.huge }
assert(not model.restore({ version = 1, providers = invalidCache }).openai.manualExpiries)
assert(next(model.restore({ version = 3, providers = merged.providers })) == nil)
assert(model.health({}, clock - 61, clock):find("无响应"))
local money = { id = "openrouter@work", display_name = "OpenRouter · work", brand = "openrouter", status = "ready",
    sections = { { type = "metric", label = "Balance", percent = 12, headline = "value", value = "$17.60", detail = "Credits left" },
        { type = "text", label = "Spent", value = "$2.40" },
        { type = "block", label = "Details", body = { "Daily: $0.10", "Monthly: $2.40" } } } }
local balanceOnly = { id = "custom:wallet", display_name = "My API", status = "ready",
    metrics = {}, sections = { { type = "block", label = "Balance", body = { "CNY -1.25" } } } }
local many = { schema_version = 1, primary = "openrouter@work", entries = { copy(report.entries[1]), money, balanceOnly,
    { id = "new-vendor", display_name = "New subscription", status = "error" } } }
local general = model.merge(nil, many, clock)
assert(#model.ids(general) == 3 and general.providers["openrouter@work"].metrics[1].headline == "value")
assert(general.providers["openrouter@work"].metrics[1].value == "$17.60")
local longName = copy(money); longName.display_name = string.rep("中", 100)
assert(utf8.len(model.entry(longName, clock).name) == 33, "label truncation split a UTF-8 character")
assert(general.providers["custom:wallet"].hasData and model.barRows(general.providers["custom:wallet"])[1].value == "CNY -1.25")
assert(general.errors["new-vendor"] and not general.providers["new-vendor"].hasData)
local namedCodex = copy(report.entries[1]); namedCodex.id = "openai@personal"; namedCodex.brand = "openai"
assert(model.entry(namedCodex, clock).manualResets == 1 and model.glyph(model.entry(namedCodex, clock)) == "brand-openai")
local generalCache = model.restore({ version = 2, providers = general.providers })
assert(generalCache["openrouter@work"].sections[2].value == "$2.40" and generalCache["custom:wallet"])
assert(not generalCache["new-vendor"], "failed-only metadata was treated as successful cache")
local failedGeneral = copy(many); failedGeneral.entries[2].status = "error"
local preserved = model.merge(general, failedGeneral, clock)
assert(preserved.providers["openrouter@work"].metrics[1].value == "$17.60" and preserved.errors["openrouter@work"])
local removed = model.merge(general, { schema_version = 1, entries = { balanceOnly } }, clock)
assert(#model.ids(removed) == 1 and not removed.providers["openai"], "removed accounts stayed in the selector")
local invalidId = copy(balanceOnly); invalidId.id = "bad\nid"
assert(#model.ids(model.merge(nil, { schema_version = 1, entries = { invalidId, invalidId } }, clock)) == 0)
local codexWithCredits = copy(report.entries[1])
local codexMetric = copy(rolling); codexMetric.type = "metric"
codexWithCredits.sections = { codexMetric, { type = "block", label = "Credits", body = { "balance: $0.00" } } }
local codexView = model.merge(nil, { schema_version = 1, entries = { codexWithCredits } }, clock)
assert(#model.sections(codexView.providers.openai) == 1, "Codex supplementary credits appeared by default")
local creditsKey = codexView.providers.openai.sections[2].key
codexView.preferences = { sections = { openai = { [creditsKey] = true } } }
assert(#model.sections(codexView.providers.openai, codexView.preferences, "openai") == 2)
assert(#model.tabIds({ providers = general.providers, preferences = { tabs = { "openai" } } }) == 1)
assert(#model.tabIds({ providers = general.providers, preferences = { tabs = {} } }) == 0)
local deepseek = copy(money); deepseek.id = "deepseek"; deepseek.display_name = "DeepSeek"
deepseek.sections[1].value = "CNY 0.00"
assert(model.entry(deepseek, clock).hasData, "a real zero API balance was hidden")


local function harness(cache)
    local state, watches, calls, writes = {}, {}, {}, {}
    local env = setmetatable({}, { __index = _G })
    env.config = { refresh_minutes = 5, timeout_seconds = 30, progress_width = 40, show_countdown = true, account_id = "openai" }
    local doc = { valid = report, partial = partial, cached = cache }
    local enabled = true
    env.noctalia = {
        getConfig = function(key) return env.config[key] end,
        nowMs = function() return clock * 1000 end,
        isDarkMode = function() return env.dark ~= false end,
        pluginDataDir = function() return "/plugin-data" end,
        setUpdateInterval = function(ms) env.interval = ms end,
        fileInfo = function() return cache and { size = 100 } or nil end,
        readFile = function() return "cached" end,
        writeFile = function(path, data) writes[path] = data; return true end,
        renameFile = function() return true end,
        json = { decode = function(value) return copy(doc[value]) end,
            encode = function(value) env.encoded = copy(value); return "encoded" end },
        runAsync = function(argv, callback, timeout)
            calls[#calls + 1] = { argv = argv, callback = callback, timeout = timeout }; return enabled
        end,
        state = {
            get = function(key) return copy(state[key]) end,
            set = function(key, value)
                state[key] = copy(value)
                for _, callback in ipairs(watches[key] or {}) do callback(copy(value)) end
            end,
            watch = function(key, callback) watches[key] = watches[key] or {}; table.insert(watches[key], callback) end,
        },
        log = function() end,
        formatTime = function(_, at) return tostring(at) end,
        togglePanel = function(id) env.toggled = id end,
        copyToClipboard = function(value) env.clipboard = value end,
    }
    env.require = function(path)
        return assert(loadfile(source .. path, "t", env))()
    end
    env.ui = setmetatable({}, { __index = function(_, kind)
        return function(props, children) return { kind = kind, props = props, children = children or {} } end
    end })
    env.renders = 0
    env.panel = { render = function(tree) env.renders = env.renders + 1; env.tree = tree end,
        close = function() env.closed = true end }
    env.barRenders = 0
    env.barWidget = { render = function(tree) env.barTree = tree; env.barRenders = env.barRenders + 1 end,
        isVertical = function() return false end, setTooltip = function(value) env.tip = value end,
        setVisible = function(value) env.visible = value end }
    function env.load(name) assert(loadfile(source .. name .. ".luau", "t", env))() end
    function env.complete(result, index) calls[index or #calls].callback(result) end
    function env.refuse() enabled = false end
    env.calls, env.state, env.writes = calls, state, writes
    return env
end
local service = harness()
service.load("service")
assert(#service.calls == 1 and service.state.snapshot.busy)
assert(service.calls[1].argv[1] == "flock" and service.calls[1].argv[7] == "-k")
for _ = 1, 100 do service.onIpc("refresh") end
assert(#service.calls == 1, "concurrent refresh spawned a process")
service.complete({ exitCode = 0, stdout = "valid" })
assert(not service.state.snapshot.busy and service.encoded.providers.openai.metrics[1].percent == 46)
clock = clock + 6; service.onIpc("refresh")
service.complete({ exitCode = 0, stdout = "partial" })
assert(service.state.snapshot.errors.openai and service.state.snapshot.providers.openai)
clock = clock + 6; service.onIpc("refresh")
service.complete({ exitCode = 0, stdout = "broken" })
assert(service.state.snapshot.error:find("JSON") and service.state.snapshot.providers.openai)
clock = clock + 6; service.onIpc("refresh")
service.complete({ exitCode = 124 })
assert(service.state.snapshot.error:find("超时"))
clock = clock + 6; service.onIpc("refresh")
local abandoned = #service.calls
clock = clock + 46; service.update()
assert(not service.state.snapshot.busy and service.state.snapshot.error:find("回调"))
service.complete({ exitCode = 0, stdout = "valid" }, abandoned)
assert(service.state.snapshot.error:find("回调"), "late result replaced current state")
clock = clock + 16; service.update()
assert(#service.calls == abandoned + 1)
service.complete({ exitCode = 75 })
clock = clock + 16; service.update()
service.complete({ exitCode = 0, stdout = "valid", stdoutTruncated = true })
assert(service.state.snapshot.error:find("截断"))
clock = clock + 301; service.update()
service.complete({ exitCode = 0, stdout = "valid" })
clock = clock + 120; service.update()
assert(service.state.snapshot.busy, "resume did not refresh")
service.complete({ exitCode = 0, stdout = "valid" })
clock = clock + 6; service.refuse(); service.onIpc("refresh")
assert(not service.state.snapshot.busy and service.state.snapshot.error:find("启动"))
local restart = harness({ version = 1, providers = merged.providers }); restart.load("service")
assert(restart.state.snapshot.providers.openai.stale)
local callsBeforePreference = #service.calls
service.noctalia.state.set("display_preferences", { tabs = { "openai" }, sections = { openai = { ["block:Credits:1"] = false } } })
assert(service.state.snapshot.preferences.tabs[1] == "openai" and service.encoded.preferences.tabs[1] == "openai")
assert(#service.calls == callsBeforePreference, "display preferences triggered a CLI query")
local preferred = harness({ version = 2, providers = general.providers, order = general.order, preferences = { tabs = { "openrouter@work" } } })
preferred.load("service")
assert(preferred.state.snapshot.preferences.tabs[1] == "openrouter@work")

local configured = harness()
configured.config.refresh_minutes, configured.config.timeout_seconds = 2, 55
configured.load("service")
assert(configured.calls[1].argv[9] == "55s" and configured.calls[1].timeout == 60000)
configured.config.timeout_seconds = 5
configured.onConfigChanged()
assert(#configured.calls == 1, "settings change duplicated an in-flight query")
for _ = 1, 4 do clock = clock + 15; configured.update() end
assert(configured.state.snapshot.busy, "timeout change shortened the current query watchdog")
configured.complete({ exitCode = 124 })
assert(configured.state.snapshot.error:find("55秒"), "in-flight timeout was replaced")
for _ = 1, 3 do clock = clock + 15; configured.update() end
assert(#configured.calls == 1, "query started before configured interval")
clock = clock + 15; configured.update()
assert(#configured.calls == 2 and configured.calls[2].argv[9] == "5s" and configured.calls[2].timeout == 10000)
configured.complete({ exitCode = 0, stdout = "valid" })
configured.config.refresh_minutes = 1
configured.onConfigChanged()
assert(#configured.calls == 2)
for _ = 1, 4 do clock = clock + 15; configured.update() end
assert(#configured.calls == 3, "new refresh interval did not take effect")
local bounded = harness()
bounded.config.refresh_minutes, bounded.config.timeout_seconds = -1, 1000
local configuredModel = bounded.require("./model.luau")
assert(configuredModel.refreshSeconds() == 60)
assert(configuredModel.settingInt("timeout_seconds", 30, 5, 55) == 55)
bounded.config.refresh_minutes = 0/0
assert(configuredModel.refreshSeconds() == 300)

local panel = harness()
panel.noctalia.state.set("snapshot", merged); panel.noctalia.state.set("heartbeat", clock)
panel.load("panel"); assert(panel.renders == 0)
panel.onOpen(); assert(panel.renders == 1)
local function find(node, key)
    if node.props.key == key then return node end
    for _, child in ipairs(node.children) do
        local result = find(child, key); if result then return result end
    end
end
assert(find(find(panel.tree, "manual-resets"), "count").props.text == "剩余 1 次")
assert(find(find(panel.tree, "expiry-1"), "remaining").props.text:find("剩余"))
assert(find(find(panel.tree, "expiry-1"), "date").props.text:find("到期"))
local expiredPanel = harness()
local expiredSnapshot = copy(merged); expiredSnapshot.providers.openai.manualExpiries = { clock - 1 }
expiredPanel.noctalia.state.set("snapshot", expiredSnapshot); expiredPanel.noctalia.state.set("heartbeat", clock)
expiredPanel.load("panel"); expiredPanel.onOpen()
assert(find(find(expiredPanel.tree, "expiry-1"), "icon").props.name == "clock-exclamation")
assert(not find(find(expiredPanel.tree, "expiry-1"), "remaining"))
local slowPanel = harness()
slowPanel.config.refresh_minutes = 120
local older = copy(merged); older.providers.openai.fetched = clock - 3600
slowPanel.noctalia.state.set("snapshot", older); slowPanel.noctalia.state.set("heartbeat", clock)
slowPanel.load("panel"); slowPanel.onOpen()
assert(find(find(slowPanel.tree, "status"), "icon").props.name == "circle-check", "long refresh interval marked data stale too soon")
local dynamic = harness()
dynamic.noctalia.state.set("snapshot", general); dynamic.noctalia.state.set("heartbeat", clock)
dynamic.load("panel"); dynamic.onOpen()
assert(find(dynamic.tree, "openai") and find(dynamic.tree, "openrouter@work") and find(dynamic.tree, "custom:wallet"))
assert(not find(dynamic.tree, "new-vendor") and not find(dynamic.tree, "provider"), "failed/unconfigured account or dropdown was shown")
local openRouterTab = find(dynamic.tree, "openrouter@work").props.onClick
openRouterTab()
assert(find(dynamic.tree, "percent").props.text == "$17.60")
assert(not find(dynamic.tree, "progress"), "balance was rendered as a made-up remaining quota")
find(dynamic.tree, "custom:wallet").props.onClick()
assert(find(dynamic.tree, "line-1").props.text == "CNY -1.25")
dynamic.toggleSettings()
find(find(dynamic.tree, "account-openrouter@work"), "enabled").props.onChange("false")
assert(#dynamic.state.display_preferences.tabs == 2)
find(find(dynamic.tree, "account-openrouter@work"), "copy").props.onClick()
assert(dynamic.clipboard == "openrouter@work")
dynamic.toggleSettings()
assert(not find(dynamic.tree, "openrouter@work") and find(dynamic.tree, "openai") and find(dynamic.tree, "custom:wallet"))
dynamic.toggleSettings()
find(find(dynamic.tree, "account-openrouter@work"), "enabled").props.onChange("true")
dynamic.toggleSettings()
assert(find(dynamic.tree, "openrouter@work").props.onClick == openRouterTab, "tab handler changed across renders")
assert(dynamic.state.refresh == nil and #dynamic.calls == 0)
local creditsPanel = harness()
codexView.preferences = nil
creditsPanel.noctalia.state.set("snapshot", codexView); creditsPanel.noctalia.state.set("heartbeat", clock)
creditsPanel.load("panel"); creditsPanel.onOpen()
assert(not find(creditsPanel.tree, "line-1"))
creditsPanel.toggleSettings()
find(find(creditsPanel.tree, "show-" .. creditsKey), "enabled").props.onChange("true")
creditsPanel.toggleSettings()
assert(find(creditsPanel.tree, "line-1").props.text == "balance: $0.00")
local function checkTree(node, keys)
    assert(type(node.props.key) == "string", "unkeyed node")
    assert(not keys[node.props.key], "duplicate sibling key"); keys[node.props.key] = true
    if node.props.onClick then assert(type(node.props.onClick) == "function" or (type(node.props.onClick) == "string" and type(panel[node.props.onClick]) == "function")) end
    if node.props.onChange then assert(type(node.props.onChange) == "function" or (type(node.props.onChange) == "string" and type(panel[node.props.onChange]) == "function")) end
    if node.props.fontWeight then
        assert(({thin=true, light=true, normal=true, medium=true, semibold=true, bold=true, heavy=true})[node.props.fontWeight], "unsupported font weight")
    end
    local childKeys = {}; for _, child in ipairs(node.children) do checkTree(child, childKeys) end
end
for _ = 1, 200 do
    panel.onIpc("select", "opencode-go"); checkTree(panel.tree, {}); assert(not find(panel.tree, "manual-resets"))
    panel.onIpc("select", "openai"); checkTree(panel.tree, {})
end
assert(#panel.calls == 0 and panel.state.refresh == nil, "selection triggered a query")
local count = panel.renders
for _ = 1, 100 do panel.update(); panel.noctalia.state.set("heartbeat", clock) end
assert(panel.renders == count, "healthy timer or heartbeat redrew panel")
panel.onKey("right", true); panel.onKey("left", true)
panel.onKey("escape", true); assert(panel.closed)
panel.refresh(); assert(panel.state.refresh == 1)
clock = clock + 61; panel.update(); assert(panel.renders == count + 3)
panel.onClose(); count = panel.renders
panel.noctalia.state.set("snapshot", merged); assert(panel.renders == count)
local bar = harness(); bar.noctalia.state.set("snapshot", merged); bar.noctalia.state.set("heartbeat", clock)
bar.load("bar")
assert(bar.barTree.children[1].props.name == "brand-openai")
assert(bar.barTree.children[2].children[1].children[1].props.progress == .54)
assert(bar.barTree.children[2].children[2].children[1].props.progress == .73)
assert(bar.barTree.children[2].props.gap == 0 and bar.barTree.children[2].children[1].props.height == 10)
assert(bar.tip:find("Codex") and not bar.tip:find("OpenCode") and #bar.calls == 0)
local renders = bar.barRenders
clock = clock + 60; bar.noctalia.state.set("heartbeat", clock); bar.update()
assert(bar.barRenders == renders + 1, "minute countdown failed to update bar")
checkTree(bar.barTree, {})
local expired = copy(merged)
expired.error = "cached"
expired.providers.openai.metrics[1].reset = clock - 1
expired.providers.openai.sections[1].reset = clock - 1
bar.noctalia.state.set("snapshot", expired)
assert(#bar.barTree.children == 2 and not find(bar.barTree, "stale"))
assert(bar.barTree.children[2].children[1].children[3].props.text == "0m")
bar.onClick(); assert(bar.toggled == "pupu/ai-usage-lite:panel")
bar.onRightClick(); assert(bar.state.refresh == 1)
bar.config.show_countdown, bar.config.progress_width = false, 72
bar.update()
assert(not find(bar.barTree.children[2].children[1], "reset"))
assert(bar.barTree.children[2].children[1].children[1].props.width == 72)
renders = bar.barRenders
clock = clock + 60; bar.noctalia.state.set("heartbeat", clock); bar.update()
assert(bar.barRenders == renders, "hidden countdown still redrew the bar")
local walletBar = harness()
walletBar.config.account_id = "openrouter@work"
walletBar.noctalia.state.set("snapshot", general); walletBar.noctalia.state.set("heartbeat", clock)
walletBar.load("bar")
assert(find(walletBar.barTree, "value").props.text == "$17.60" and not find(walletBar.barTree, "progress"))
assert(walletBar.tip:find("OpenRouter"))
assert(walletBar.barTree.children[1].kind == "image")
assert(walletBar.barTree.children[1].props.path == "icons/openrouter-dark.svg")
walletBar.dark = false; walletBar.update()
assert(walletBar.barTree.children[1].props.path == "icons/openrouter-light.svg")
local logoModel = walletBar.require("./model.luau")
assert(logoModel.logo({brand="opencode-go"}) == "icons/opencode-light.svg")
assert(logoModel.logo({brand="deepseek"}) == "icons/deepseek-light.svg")
assert(logoModel.logo({brand="../../private"}) == nil)
assert(logoModel.icon({brand="unknown"}, "unknown", 17, "primary").props.name == "brain")
assert(logoModel.icon({brand="copilot"}, "copilot", 17, "primary").props.name == "brand-github-copilot")
assert(logoModel.logo(logoModel.entry(money, clock)) == "icons/openrouter-light.svg", "named account lost its brand")
for brand, name in pairs({anthropic="claude", anthropic_api="anthropic", zai="zai", openrouter="openrouter", deepseek="deepseek",
    deepinfra="deepinfra", kimi="kimi", kilo="kilocode", novita="novita", moonshot="moonshot", grok="grok", supergrok="grok",
    grokbot="grok", antigravity="antigravity", cursor="cursor", minimax="minimax", kiro="kiro", nous="nousresearch",
    ["opencode-go"]="opencode", commandcode="commandcode", ollama="ollama", modelstudio="alibabacloud", devin="devin", cline="cline"}) do
    for _, dark in ipairs({true, false}) do
        walletBar.dark = dark
        local path = logoModel.logo({brand=brand})
        assert(path == "icons/" .. name .. (dark and "-dark.svg" or "-light.svg"))
        local asset = assert(io.open(path)); local svg = asset:read("a"); asset:close()
        assert(svg:find("<svg") and not svg:find("currentColor") and not svg:find("href="), path)
    end
end
assert(bar.config.account_id == "openai" and bar.barTree.children[1].props.name == "brand-openai", "one widget changed another widget's account")
walletBar.config.account_id = "new-vendor"
walletBar.noctalia.state.set("snapshot", general)
assert(not walletBar.visible, "failed-only widget account was shown")
local emptyPanel = harness(); emptyPanel.load("panel"); emptyPanel.onOpen()
assert(find(emptyPanel.tree, "empty") and #find(emptyPanel.tree, "tabs").children == 0)
print("PASS: generic providers/accounts, currency/value/text/block sections, visible-data tabs, independent widget accounts, display preferences/cache, partial errors, dates, schema, legacy cache migration, configurable scheduling, concurrency/watchdog/resume, 400 switches, stable callbacks, no timer panel renders")
