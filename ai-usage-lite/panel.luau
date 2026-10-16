local model = require("./model.luau")
local selected, opened = "openai", false
local snapshot = noctalia.state.get("snapshot") or {}
local lastHealth

local function label(key, text, color, size, weight)
    return ui.label({ key = key, text = text, color = color or "on_surface", fontSize = size or 11,
        fontWeight = weight or "normal", maxLines = 2 })
end

local function tab(id, title, glyph, callback)
    local active = selected == id
    return ui.row({ key = id, flexGrow = 1, gap = 6, paddingV = 8, paddingH = 10, radius = 8,
        justify = "center", align = "center", fill = active and "primary/0.12" or "on_surface/0.025",
        border = active and "primary/0.25" or "outline/0.08", borderWidth = 1, onClick = callback }, {
        ui.glyph({ key = "icon", name = glyph, size = 15, color = active and "primary" or "on_surface_variant" }),
        label("title", title, active and "primary" or "on_surface_variant", 12, "semibold"),
    })
end

local function render()
    if not opened then return end
    local time = noctalia.nowMs() / 1000
    local entry = snapshot.providers and snapshot.providers[selected]
    lastHealth = model.health(snapshot, noctalia.state.get("heartbeat"), time)
    local errorText = lastHealth or (snapshot.errors and snapshot.errors[selected])
    local stale = entry and (entry.stale or time - entry.fetched > model.refreshSeconds() * 2 or errorText)
    local cards = {}
    if entry then
        cards[#cards + 1] = ui.row({ key = "plan", align = "center", gap = 6 }, {
            label("name", entry.plan, "on_surface_variant", 10),
            ui.spacer({ key = "space", flexGrow = 1 }),
            ui.row({ key = "status", tooltip = errorText or (stale and "上次成功数据，等待刷新确认" or "已同步"), align = "center" }, {
                ui.glyph({ key = "icon", name = stale and "clock-exclamation" or "circle-check", size = 13,
                    color = stale and "error" or "secondary" }),
            }),
        })
        for i, metric in ipairs(entry.metrics) do
            local remaining = math.max(0, 100 - metric.percent)
            local role = remaining <= 10 and "error" or "primary"
            local title = metric.window == 18000 and "5 小时额度" or metric.window == 604800 and "每周额度"
                or metric.label == "Monthly" and "月度额度" or metric.label
            local reset = metric.reset and noctalia.formatTime("%m-%d %H:%M", metric.reset) or "未知"
            local expired = metric.reset and metric.reset <= time
            cards[#cards + 1] = ui.column({ key = "metric-" .. selected .. "-" .. i, gap = 9,
                padding = 12, fill = "surface_variant/0.28", border = "outline/0.10", borderWidth = 1, radius = 10 }, {
                ui.row({ key = "heading", gap = 8, align = "center" }, {
                    label("name", title, "on_surface", 13, "semibold"),
                    ui.spacer({ key = "space", flexGrow = 1 }),
                    label("remaining", "剩余", "on_surface_variant", 10),
                    label("percent", string.format("%.0f%%", remaining), role, 19, "bold"),
                }),
                ui.progress({ key = "progress", progress = remaining / 100, height = 5, radius = 3,
                    fill = role, track = "on_surface/0.08" }),
                ui.row({ key = "reset", gap = 4, align = "center",
                    tooltip = expired and "重置时刻已到，等待查询确认额度" or "倒计时在打开、切换或数据更新时计算" }, {
                    ui.glyph({ key = "clock", name = expired and "clock-exclamation" or "clock", size = 11,
                        color = expired and "error" or "on_surface_variant" }),
                    label("time", (expired and "" or model.duration(metric.reset, time) .. " · ") .. reset .. " 重置", "on_surface_variant", 11),
                    ui.spacer({ key = "space", flexGrow = 1 }),
                    label("used", string.format("已用 %.0f%%", metric.percent), "on_surface_variant", 10),
                }),
            })
        end
        if selected == "openai" and entry.manualResets ~= nil then
            local resetRows = { ui.row({ key = "heading", gap = 7, align = "center" }, {
                ui.glyph({ key = "icon", name = "ticket", size = 15, color = "primary" }),
                label("name", "手动重置", "on_surface", 12, "semibold"),
                ui.spacer({ key = "space", flexGrow = 1 }),
                label("count", string.format("剩余 %d 次", entry.manualResets), "primary", 13, "semibold"),
            }) }
            for i, expiry in ipairs(entry.manualExpiries or {}) do
                local expired = expiry <= time
                local details = {
                    ui.glyph({ key = "icon", name = expired and "clock-exclamation" or "clock", size = 11,
                        color = expired and "error" or "on_surface_variant" }),
                }
                if not expired then details[#details + 1] = label("remaining", "剩余 " .. model.duration(expiry, time), "on_surface_variant", 11) end
                details[#details + 1] = ui.spacer({ key = "space", flexGrow = 1 })
                details[#details + 1] = label("date", noctalia.formatTime("%Y-%m-%d %H:%M", expiry) .. " 到期", "on_surface_variant", 11)
                resetRows[#resetRows + 1] = ui.row({ key = "expiry-" .. i, gap = 4, align = "center",
                    tooltip = expired and "重置卡已过期，次数待查询确认" or "重置卡到期时间（本地）" }, details)
            end
            cards[#cards + 1] = ui.column({ key = "manual-resets", gap = 9, padding = 12,
                fill = "surface_variant/0.20", border = "outline/0.10", borderWidth = 1, radius = 10 }, resetRows)
        end
    else
        cards[#cards + 1] = ui.column({ key = "empty", gap = 10, padding = 25, align = "center" }, {
            ui.glyph({ key = "icon", name = selected == "openai" and "brand-openai" or "code", size = 28, color = "on_surface_variant" }),
            label("message", snapshot.busy and "正在查询额度…" or errorText and "查询失败" or "暂无可用数据", "on_surface_variant", 12),
        })
    end
    -- v5.2.1 has no label patch API: no timer-driven panel.render().
    panel.render(ui.column({ key = "root", gap = 12, padding = 14, flexGrow = 1 }, {
        ui.row({ key = "heading", gap = 8, align = "center" }, {
            ui.row({ key = "badge", width = 28, height = 28, radius = 8, fill = "primary/0.10", align = "center", justify = "center" }, {
                ui.glyph({ key = "icon", name = selected == "openai" and "brand-openai" or "code", size = 17, color = "primary" }),
            }),
            label("title", "AI 用量", "on_surface", 14, "bold"),
            ui.spacer({ key = "space", flexGrow = 1 }),
            ui.button({ key = "refresh", glyph = snapshot.busy and "loader-2" or "refresh", tooltip = snapshot.busy and "查询中…" or "刷新用量",
                variant = "ghost", controlSize = "sm", width = 30, enabled = not snapshot.busy, onClick = "refresh" }),
            ui.button({ key = "close", glyph = "x", tooltip = "关闭", variant = "ghost", controlSize = "sm", width = 30, onClick = "close" }),
        }),
        ui.row({ key = "tabs", gap = 6 }, {
            tab("openai", "Codex", "brand-openai", "selectCodex"),
            tab("opencode-go", "OpenCode Go", "code", "selectGo"),
        }),
        ui.scroll({ key = "details", gap = 10, flexGrow = 1 }, cards),
        ui.row({ key = "footer", gap = 4, align = "center", tooltip = snapshot.cacheError or errorText or "数据时间 · 本地时区" }, {
            ui.glyph({ key = "clock", name = (snapshot.cacheError or (not entry and errorText)) and "alert-circle" or "clock", size = 11,
                color = (snapshot.cacheError or (not entry and errorText)) and "error" or "on_surface_variant" }),
            label("fetched", entry and ("更新于 " .. noctalia.formatTime("%H:%M", entry.fetched)) or "等待更新", "on_surface_variant", 10),
            ui.spacer({ key = "space", flexGrow = 1 }),
            label("timezone", "本地时间", "on_surface_variant", 10),
        }),
    }))
end

function selectCodex() selected = "openai"; render() end
function selectGo() selected = "opencode-go"; render() end
function refresh() model.request() end
function close() panel.close() end
function onOpen() opened = true; snapshot = noctalia.state.get("snapshot") or {}; render() end
function onClose() opened = false end
function onKey(chord, pressed)
    if not pressed or pressed == "false" then return end
    local key = tostring(chord):lower()
    if key == "escape" then close()
    elseif key == "r" then refresh()
    elseif key == "left" then selectCodex()
    elseif key == "right" then selectGo() end
end
function onIpc(event, payload)
    if event == "select" then
        if payload == "openai" then selectCodex() elseif payload == "opencode-go" then selectGo() end
    elseif event == "refresh" then refresh()
    elseif event == "status" then noctalia.log("panel selected=" .. selected .. " opened=" .. tostring(opened)) end
end
noctalia.state.watch("snapshot", function(value) snapshot = value or {}; render() end)
noctalia.state.watch("heartbeat", function(value)
    local health = model.health(snapshot, value, noctalia.nowMs() / 1000)
    if health ~= lastHealth then render() end
end)
noctalia.setUpdateInterval(30000)
function update()
    if not opened then return end
    local health = model.health(snapshot, noctalia.state.get("heartbeat"), noctalia.nowMs() / 1000)
    if health ~= lastHealth then render() end
end
