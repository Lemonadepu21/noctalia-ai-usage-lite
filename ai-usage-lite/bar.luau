local model = require("./model.luau")
local snapshot = noctalia.state.get("snapshot") or {}
local previousView, previousTip

function update()
    local time = noctalia.nowMs() / 1000
    local entry = snapshot.providers and snapshot.providers.openai
    local errorText = model.health(snapshot, noctalia.state.get("heartbeat"), time)
        or (snapshot.errors and snapshot.errors.openai)
    local stale = entry and (entry.stale or time - entry.fetched > 600 or errorText)
    local signature = { entry and "data" or tostring(snapshot.busy) }
    local rows, tips = {}, { "Codex · 剩余额度\n上：5 小时 · 下：每周\n点击查看详情 · 右键刷新" }
    if entry then
        for i, metric in ipairs(entry.metrics) do
            local remaining = math.max(0, 100 - metric.percent)
            local role = remaining <= 10 and "error" or i == 1 and "primary" or "secondary"
            local reset = model.duration(metric.reset, time):gsub("小时", "h"):gsub("天", "d"):gsub("分", "m")
            if not metric.reset then reset = "—" elseif metric.reset <= time then reset = "0m" end
            signature[#signature + 1] = string.format("%s/%s/%s", metric.percent, reset, metric.reset)
            rows[#rows + 1] = ui.row({ key = "window-" .. i, gap = 5, height = 10, align = "center" }, {
                ui.progress({ key = "progress", progress = remaining / 100, width = 40, height = 4,
                    radius = 2, fill = role, track = "on_surface/0.12" }),
                ui.label({ key = "percent", text = string.format("%.0f%%", remaining), width = 28,
                    fontSize = 13, fontWeight = "semibold", color = role, maxLines = 1 }),
                ui.label({ key = "reset", text = reset, width = 44, fontSize = 11,
                    color = "on_surface_variant", maxLines = 1 }),
            })
            tips[#tips + 1] = string.format("%s 剩余 %.0f%% · %s", metric.label, remaining, model.duration(metric.reset, time))
                .. (metric.reset and ("\n重置 " .. noctalia.formatTime("%m-%d %H:%M", metric.reset)) or "")
        end
    else
        rows[1] = ui.label({ key = "empty", text = snapshot.busy and "查询中…" or "暂无额度",
            fontSize = 11, color = "on_surface_variant" })
    end
    if errorText then tips[#tips + 1] = errorText end
    if stale then tips[#tips + 1] = "显示上次成功数据" end
    local view = table.concat(signature, "|")
    if view ~= previousView then
        local children = {
            ui.glyph({ key = "codex", name = "brand-openai", size = 17, color = "on_surface" }),
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

function onClick() noctalia.togglePanel("pupu/ai-usage-lite:panel") end
function onRightClick() model.request() end
noctalia.state.watch("snapshot", function(value) snapshot = value or {}; update() end)
noctalia.setUpdateInterval(60000)
update()
