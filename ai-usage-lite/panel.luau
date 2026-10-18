local model = require("./model.luau")
local selected, opened = nil, false
local selectorIds = {}
local snapshot = noctalia.state.get("snapshot") or {}
local lastHealth

local function label(key, text, color, size, weight)
    return ui.label({ key = key, text = text, color = color or "on_surface", fontSize = size or 11,
        fontWeight = weight or "normal", maxLines = 2 })
end

local function metricCard(metric, key, time)
    local percent = metric.headline ~= "value"
    local remaining = math.max(0, 100 - metric.percent)
    local role = percent and remaining <= 10 and "error" or "primary"
    local rows = { ui.row({ key = "heading", gap = 8, align = "center" }, {
        label("name", metric.label, "on_surface", 12, "semibold"),
        ui.spacer({ key = "space", flexGrow = 1 }),
        label("remaining", percent and "剩余" or "", "on_surface_variant", 10),
        label("percent", percent and string.format("%.0f%%", remaining) or metric.value, role, 19, "bold"),
    }) }
    if percent then
        rows[#rows + 1] = ui.progress({ key = "progress", progress = remaining / 100, height = 5,
            radius = 3, fill = role, track = "on_surface/0.08" })
    end
    if metric.reset then
        local expired = metric.reset <= time
        rows[#rows + 1] = ui.row({ key = "reset", gap = 4, align = "center", tooltip = metric.detail }, {
            ui.glyph({ key = "clock", name = expired and "clock-exclamation" or "clock", size = 11,
                color = expired and "error" or "on_surface_variant" }),
            label("time", (expired and "" or model.duration(metric.reset, time) .. " · ")
                .. noctalia.formatTime("%m-%d %H:%M", metric.reset) .. " 重置", "on_surface_variant", 11),
        })
    elseif metric.detail ~= "" then
        rows[#rows + 1] = label("detail", metric.detail, "on_surface_variant", 11)
    end
    if percent then rows[#rows + 1] = label("used", metric.value ~= "" and metric.value
        or string.format("已用 %.0f%%", metric.percent), "on_surface_variant", 10) end
    return ui.column({ key = key, gap = 8, padding = 12, fill = "surface_variant/0.28",
        border = "outline/0.10", borderWidth = 1, radius = 10 }, rows)
end

local function render()
    if not opened then return end
    local time = noctalia.nowMs() / 1000
    local providers = snapshot.providers or {}
    if not selected or not providers[selected] then selected = model.barId(snapshot) end
    local entry = selected and providers[selected]
    selectorIds = model.ids(snapshot)
    local options, selectedIndex = {}, -1
    for i, id in ipairs(selectorIds) do
        options[i] = providers[id].name .. ((snapshot.errors and snapshot.errors[id]) and " · !" or "")
        if id == selected then selectedIndex = i - 1 end
    end
    lastHealth = model.health(snapshot, noctalia.state.get("heartbeat"), time)
    local errorText = lastHealth or (snapshot.errors and snapshot.errors[selected])
    local stale = entry and entry.hasData and (entry.stale or time - entry.fetched > model.refreshSeconds() * 2 or errorText)
    local cards = {}
    if entry and entry.hasData then
        cards[#cards + 1] = ui.row({ key = "plan", align = "center", gap = 6 }, {
            label("name", entry.plan, "on_surface_variant", 10),
            ui.spacer({ key = "space", flexGrow = 1 }),
            ui.row({ key = "status", tooltip = errorText or (stale and "上次成功数据，等待刷新确认" or "已同步"), align = "center" }, {
                ui.glyph({ key = "icon", name = stale and "clock-exclamation" or "circle-check", size = 13,
                    color = stale and "error" or "secondary" }),
            }),
        })
        for i, section in ipairs(entry.sections) do
            local key = "section-" .. selected .. "-" .. i
            if section.type == "metric" then
                cards[#cards + 1] = metricCard(section, key, time)
            elseif not (entry.manualResets ~= nil and section.label == "Reset credits") then
                local rows = { label("title", section.label, "on_surface_variant", 11, "semibold") }
                if section.type == "text" then
                    rows[#rows + 1] = label("value", section.value, "on_surface", 15, "semibold")
                else
                    for j, line in ipairs(section.body) do rows[#rows + 1] = label("line-" .. j, line, "on_surface", 12) end
                end
                cards[#cards + 1] = ui.column({ key = key, gap = 7, padding = 12, radius = 10,
                    fill = "surface_variant/0.20", border = "outline/0.10", borderWidth = 1 }, rows)
            end
        end
        if entry.manualResets ~= nil then
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
            ui.glyph({ key = "icon", name = model.glyph(entry), size = 28, color = "on_surface_variant" }),
            label("message", snapshot.busy and "正在查询额度…" or errorText and "查询失败" or "暂无可用数据", "on_surface_variant", 12),
        })
    end
    -- v5.2.1 has no label patch API: no timer-driven panel.render().
    panel.render(ui.column({ key = "root", gap = 12, padding = 14, flexGrow = 1 }, {
        ui.row({ key = "heading", gap = 8, align = "center" }, {
            ui.row({ key = "badge", width = 28, height = 28, radius = 8, fill = "primary/0.10", align = "center", justify = "center" }, {
                ui.glyph({ key = "icon", name = model.glyph(entry), size = 17, color = "primary" }),
            }),
            label("title", "AI 用量", "on_surface", 14, "bold"),
            ui.spacer({ key = "space", flexGrow = 1 }),
            ui.button({ key = "refresh", glyph = snapshot.busy and "loader-2" or "refresh", tooltip = snapshot.busy and "查询中…" or "刷新用量",
                variant = "ghost", controlSize = "sm", width = 30, enabled = not snapshot.busy, onClick = "refresh" }),
            ui.button({ key = "close", glyph = "x", tooltip = "关闭", variant = "ghost", controlSize = "sm", width = 30, onClick = "close" }),
        }),
        ui.row({ key = "accounts", gap = 6, align = "center" }, {
            ui.select({ key = "provider", options = options, selectedIndex = selectedIndex,
                placeholder = "CLI 尚未返回账户", enabled = #options > 0, flexGrow = 1,
                controlSize = "sm", onChange = "selectProvider" }),
            ui.button({ key = "pin", glyph = "pin", selected = selected == model.barId(snapshot),
                enabled = selected ~= nil, variant = "ghost", controlSize = "sm", width = 30,
                tooltip = selected == model.barId(snapshot) and "已显示在状态栏" or "设为状态栏账户", onClick = "pinProvider" }),
        }),
        ui.scroll({ key = "details", gap = 10, flexGrow = 1 }, cards),
        ui.row({ key = "footer", gap = 4, align = "center", tooltip = snapshot.cacheError or errorText or "数据时间 · 本地时区" }, {
            ui.glyph({ key = "clock", name = (snapshot.cacheError or ((not entry or not entry.hasData) and errorText)) and "alert-circle" or "clock", size = 11,
                color = (snapshot.cacheError or ((not entry or not entry.hasData) and errorText)) and "error" or "on_surface_variant" }),
            label("fetched", entry and entry.hasData and ("更新于 " .. noctalia.formatTime("%H:%M", entry.fetched)) or "等待更新", "on_surface_variant", 10),
            ui.spacer({ key = "space", flexGrow = 1 }),
            label("timezone", "本地时间", "on_surface_variant", 10),
        }),
    }))
end

local function selectId(id)
    if (snapshot.providers or {})[id] then selected = id; render() end
end
function selectProvider(index)
    local number = tonumber(index)
    if number and number % 1 == 0 and number >= 0 and selectorIds[number + 1] then selectId(selectorIds[number + 1]) end
end
function pinProvider()
    if selected then noctalia.state.set("bar_provider", selected) end
end
local function step(direction)
    for i, id in ipairs(selectorIds) do
        if id == selected then selectId(selectorIds[(i - 1 + direction) % #selectorIds + 1]); return end
    end
end
function refresh() model.request() end
function close() panel.close() end
function onOpen() opened = true; snapshot = noctalia.state.get("snapshot") or {}; render() end
function onClose() opened = false end
function onKey(chord, pressed)
    if not pressed or pressed == "false" then return end
    local key = tostring(chord):lower()
    if key == "escape" then close()
    elseif key == "r" then refresh()
    elseif key == "left" then step(-1)
    elseif key == "right" then step(1) end
end
function onIpc(event, payload)
    if event == "select" then
        if type(payload) == "string" then selectId(payload) end
    elseif event == "refresh" then refresh()
    elseif event == "status" then noctalia.log("panel selected=" .. tostring(selected) .. " opened=" .. tostring(opened)) end
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
