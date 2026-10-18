local model = require("./model.luau")
local snapshot = noctalia.state.get("snapshot") or {}
local previousView, previousTip

function update()
    local time = noctalia.nowMs() / 1000
    local id = model.barId(snapshot, noctalia.getConfig("account_id"))
    local entry = id and snapshot.providers[id]
    local errorText = model.health(snapshot, noctalia.state.get("heartbeat"), time)
        or (snapshot.errors and snapshot.errors[id])
    local stale = entry and entry.hasData and (entry.stale or time - entry.fetched > model.refreshSeconds() * 2 or errorText)
    local width = model.settingInt("progress_width", 40, 24, 100)
    local countdown = noctalia.getConfig("show_countdown") ~= false
    local signature = { id or "none", entry and "data" or tostring(snapshot.busy), tostring(width), tostring(countdown) }
    local rows, tips = {}, { (entry and entry.name or "AI 用量") .. "\n点击查看详情 · 右键刷新" }
    if entry then
        for i, metric in ipairs(model.barRows(entry, snapshot.preferences, id)) do
            local percent = metric.type == "metric" and metric.headline ~= "value"
            local remaining = percent and math.max(0, 100 - metric.percent) or nil
            local role = percent and remaining <= 10 and "error" or i == 1 and "primary" or "secondary"
            local reset = model.duration(metric.reset, time):gsub("小时", "h"):gsub("天", "d"):gsub("分", "m")
            if not metric.reset then reset = "—" elseif metric.reset <= time then reset = "0m" end
            signature[#signature + 1] = string.format("%s/%s/%s/%s", metric.headline, metric.percent, metric.value, countdown and reset or "")
            local cells = {}
            if percent then
                cells[#cells + 1] = ui.progress({ key = "progress", progress = remaining / 100, width = width, height = 4,
                    radius = 2, fill = role, track = "on_surface/0.12" })
                cells[#cells + 1] = ui.label({ key = "percent", text = string.format("%.0f%%", remaining), width = 28,
                    fontSize = 13, fontWeight = "semibold", color = role, maxLines = 1 })
            else
                cells[#cells + 1] = ui.label({ key = "value", text = metric.value, maxWidth = width + 80,
                    fontSize = 12, fontWeight = "semibold", color = role, maxLines = 1 })
            end
            if countdown and metric.reset then
                cells[#cells + 1] = ui.label({ key = "reset", text = reset, width = 44, fontSize = 11,
                    color = "on_surface_variant", maxLines = 1 })
            end
            rows[#rows + 1] = ui.row({ key = "window-" .. i, gap = 5, height = 10, align = "center" }, cells)
            tips[#tips + 1] = metric.label .. " · " .. (percent and string.format("剩余 %.0f%%", remaining) or metric.value)
                .. (metric.reset and ("\n重置 " .. noctalia.formatTime("%m-%d %H:%M", metric.reset)) or "")
        end
    end
    if #rows == 0 then
        rows[1] = ui.label({ key = "empty", text = snapshot.busy and "查询中…" or "暂无用量",
            fontSize = 11, color = "on_surface_variant" })
    end
    if errorText then tips[#tips + 1] = errorText end
    if stale then tips[#tips + 1] = "显示上次成功数据" end
    barWidget.setVisible(entry ~= nil and #model.barRows(entry, snapshot.preferences, id) > 0)
    local view = table.concat(signature, "|")
    if view ~= previousView then
        local children = {
            ui.glyph({ key = "provider", name = model.glyph(entry), size = 17, color = "on_surface" }),
            ui.column({ key = "windows", gap = 0 }, rows),
        }
        local container = barWidget.isVertical() and ui.column or ui.row
        barWidget.render(container({ key = "root", gap = 7, align = "center" }, children))
        previousView = view
    end
    -- Minute updates reconcile this small keyed row; the popup never ticks its tree.
    local tip = table.concat(tips, "\n")
    if tip ~= previousTip then barWidget.setTooltip(tip); previousTip = tip end
end

function onClick()
    noctalia.state.set("panel_account", model.barId(snapshot, noctalia.getConfig("account_id")))
    noctalia.togglePanel("pupu/ai-usage-lite:panel")
end
function onRightClick() model.request() end
noctalia.state.watch("snapshot", function(value) snapshot = value or {}; update() end)
noctalia.setUpdateInterval(60000)
update()
