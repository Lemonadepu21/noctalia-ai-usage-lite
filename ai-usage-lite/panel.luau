local model = require("./model.luau")
local selected, opened = nil, false
local tabIds = {}
local managing = false
local actions = {}
local render
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
        local details = {
            ui.glyph({ key = "clock", name = expired and "clock-exclamation" or "clock", size = 11,
                color = expired and "error" or "on_surface_variant" }),
            label("time", (expired and "" or model.duration(metric.reset, time) .. " · ")
                .. noctalia.formatTime("%m-%d %H:%M", metric.reset) .. " 重置", "on_surface_variant", 11),
        }
        if percent then
            details[#details + 1] = ui.spacer({ key = "space", flexGrow = 1 })
            details[#details + 1] = label("used", "已用 " .. (metric.value ~= "" and metric.value
                or string.format("%.0f%%", metric.percent)), "on_surface_variant", 10)
        end
        rows[#rows + 1] = ui.row({ key = "reset", gap = 4, align = "center", tooltip = metric.detail }, details)
    elseif metric.detail ~= "" then
        rows[#rows + 1] = label("detail", metric.detail, "on_surface_variant", 11)
    end
    if percent and not metric.reset then rows[#rows + 1] = label("used", "已用 " .. (metric.value ~= "" and metric.value
        or string.format("%.0f%%", metric.percent)), "on_surface_variant", 10) end
    return ui.column({ key = key, gap = 8, padding = 12, fill = "surface_variant/0.28",
        border = "outline/0.10", borderWidth = 1, radius = 10 }, rows)
end

local function commitPreferences(prefs)
    snapshot.preferences = prefs
    noctalia.state.set("display_preferences", prefs)
    render()
end

local function accountActions(id)
    if not actions[id] then
        actions[id] = {
            select = function() selected = id; render() end,
            copy = function() noctalia.copyToClipboard(id) end,
            tab = function(value)
                local prefs = model.preferences(snapshot.preferences)
                local tabs = {}
                for _, item in ipairs(prefs.tabs or model.tabIds(snapshot)) do if item ~= id then tabs[#tabs + 1] = item end end
                if value == true or value == "true" then tabs[#tabs + 1] = id end
                prefs.tabs = tabs
                commitPreferences(prefs)
            end,
            sections = {},
        }
    end
    return actions[id]
end

local function sectionAction(id, key)
    local handlers = accountActions(id).sections
    if not handlers[key] then
        handlers[key] = function(value)
            local prefs = model.preferences(snapshot.preferences)
            prefs.sections[id] = prefs.sections[id] or {}
            prefs.sections[id][key] = value == true or value == "true"
            commitPreferences(prefs)
        end
    end
    return handlers[key]
end

local function tabsView(providers)
    local rows, cells = {}, {}
    for i, id in ipairs(tabIds) do
        local active = selected == id
        cells[#cells + 1] = ui.row({ key = id, flexGrow = 1, gap = 6, paddingV = 8, paddingH = 10, radius = 8,
            justify = "center", align = "center", fill = active and "primary/0.12" or "on_surface/0.025",
            border = active and "primary/0.25" or "outline/0.08", borderWidth = 1,
            tooltip = providers[id].name, onClick = accountActions(id).select }, {
            model.icon(providers[id], "icon", 15, active and "primary" or "on_surface_variant"),
            label("title", providers[id].name, active and "primary" or "on_surface_variant", 12, "semibold"),
        })
        if i % 2 == 0 or i == #tabIds then
            rows[#rows + 1] = ui.row({ key = "row-" .. id, gap = 6 }, cells); cells = {}
        end
    end
    if #rows > 2 then return ui.scroll({ key = "tabs", height = 80, gap = 6 }, rows) end
    return ui.column({ key = "tabs", gap = 6 }, rows)
end

local function settingsView(providers, available, entry)
    local shown, rows = {}, { label("tabs-title", "展开页 Tab", "on_surface", 12, "semibold") }
    for _, id in ipairs(tabIds) do shown[id] = true end
    for _, id in ipairs(available) do
        rows[#rows + 1] = ui.row({ key = "account-" .. id, gap = 8, align = "center", padding = 8, radius = 8,
            fill = selected == id and "primary/0.08" or "surface_variant/0.15" }, {
            model.icon(providers[id], "icon", 17, "on_surface"),
            ui.column({ key = "name", flexGrow = 1, gap = 3, onClick = accountActions(id).select }, {
                label("title", providers[id].name, "on_surface", 12, "semibold"),
                label("id", id, "on_surface_variant", 10),
            }),
            ui.button({ key = "copy", glyph = "copy", variant = "ghost", controlSize = "sm", width = 26,
                tooltip = "复制账户 ID，用于状态栏组件设置", onClick = accountActions(id).copy }),
            ui.toggle({ key = "enabled", checked = shown[id] == true, onChange = accountActions(id).tab }),
        })
    end
    if entry then
        rows[#rows + 1] = ui.separator({ key = "separator", spacing = 5 })
        rows[#rows + 1] = label("sections-title", entry.name .. " · 显示项目", "on_surface", 12, "semibold")
        local sections = {}
        for _, item in ipairs(entry.sections) do
            if not (entry.manualResets ~= nil and item.label == "Reset credits") then sections[#sections + 1] = item end
        end
        if entry.manualResets ~= nil then sections[#sections + 1] = { key = "manual-resets", label = "手动重置卡" } end
        for _, item in ipairs(sections) do
            rows[#rows + 1] = ui.row({ key = "show-" .. item.key, gap = 8, align = "center", padding = 8 }, {
                ui.column({ key = "name", flexGrow = 1 }, { label("title", item.label, "on_surface", 12) }),
                ui.toggle({ key = "enabled", checked = model.shown(entry, snapshot.preferences, selected, item),
                    onChange = sectionAction(selected, item.key) }),
            })
        end
    end
    return ui.scroll({ key = "settings", gap = 6, flexGrow = 1 }, rows)
end

render = function()
    if not opened then return end
    local time = noctalia.nowMs() / 1000
    local providers = snapshot.providers or {}
    local available = model.ids(snapshot)
    tabIds = model.tabIds(snapshot)
    local allowed = managing and available or tabIds
    local valid = false
    for _, id in ipairs(allowed) do if selected == id then valid = true end end
    if not valid then selected = allowed[1] end
    local entry = selected and providers[selected]
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
        for i, section in ipairs(model.sections(entry, snapshot.preferences, selected)) do
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
        if entry.manualResets ~= nil and model.shown(entry, snapshot.preferences, selected, { key = "manual-resets" }) then
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
            model.icon(entry, "icon", 28, "on_surface_variant"),
            label("message", snapshot.busy and "正在查询用量…" or #available > 0 and "请在右上角选择显示的用量" or "暂无可用数据", "on_surface_variant", 12),
        })
    end
    -- v5.2.1 has no label patch API: no timer-driven panel.render().
    panel.render(ui.column({ key = "root", gap = 12, padding = 14, flexGrow = 1 }, {
        ui.row({ key = "heading", gap = 8, align = "center" }, {
            ui.row({ key = "badge", width = 28, height = 28, radius = 8, fill = "primary/0.10", align = "center", justify = "center" }, {
                model.icon(entry, "icon", 17, "primary"),
            }),
            label("title", managing and "显示设置" or "AI 用量", "on_surface", 14, "bold"),
            ui.spacer({ key = "space", flexGrow = 1 }),
            ui.button({ key = "refresh", glyph = snapshot.busy and "loader-2" or "refresh", tooltip = snapshot.busy and "查询中…" or "刷新用量",
                variant = "ghost", controlSize = "sm", width = 30, enabled = not snapshot.busy, onClick = "refresh" }),
            ui.button({ key = "display-settings", glyph = managing and "arrow-left" or "adjustments",
                tooltip = managing and "返回用量" or "选择 Tab 和显示项目", variant = "ghost", controlSize = "sm", width = 30, onClick = "toggleSettings" }),
            ui.button({ key = "close", glyph = "x", tooltip = "关闭", variant = "ghost", controlSize = "sm", width = 30, onClick = "close" }),
        }),
        managing and ui.column({ key = "no-tabs", height = 0 }, {}) or tabsView(providers),
        managing and settingsView(providers, available, entry) or ui.scroll({ key = "details", gap = 10, flexGrow = 1 }, cards),
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
    local entry = (snapshot.providers or {})[id]
    if entry and entry.hasData then selected = id; render() end
end
function toggleSettings() managing = not managing; render() end
local function step(direction)
    for i, id in ipairs(tabIds) do
        if id == selected then selectId(tabIds[(i - 1 + direction) % #tabIds + 1]); return end
    end
end
function refresh() model.request() end
function close() panel.close() end
function onOpen()
    opened = true; managing = false
    snapshot = noctalia.state.get("snapshot") or {}
    selected = noctalia.state.get("panel_account") or selected
    render()
end
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
    elseif event == "settings" then managing = true; render()
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
