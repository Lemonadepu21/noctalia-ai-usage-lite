local M = {}
M.ids = { "openai", "opencode-go" }
M.names = { openai = "Codex", ["opencode-go"] = "OpenCode Go" }

local function finite(n)
    return type(n) == "number" and n == n and math.abs(n) < math.huge
end

local function count(value)
    return finite(value) and value >= 0 and value % 1 == 0 and value or nil
end

function M.settingInt(key, default, minimum, maximum)
    local value = noctalia.getConfig(key)
    if not finite(value) then return default end
    return math.max(minimum, math.min(maximum, math.floor(value)))
end

function M.refreshSeconds()
    return M.settingInt("refresh_minutes", 5, 1, 120) * 60
end

-- Calendar arithmetic keeps UTC independent of the machine's timezone and DST.
function M.epoch(value)
    if type(value) ~= "string" then return nil end
    local y, mo, d, h, mi, s, tail = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)(.*)$")
    if not y then return nil end
    y, mo, d, h, mi, s = tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi), tonumber(s)
    local leap = y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)
    local days = { 31, leap and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    if y < 1970 or mo < 1 or mo > 12 or d < 1 or d > days[mo] or h > 23 or mi > 59 or s > 59 then return nil end
    tail = tail:gsub("^%.%d+", "")
    local offset = 0
    if tail ~= "Z" then
        local sign, oh, om = tail:match("^([+-])(%d%d):(%d%d)$")
        if not sign or tonumber(oh) > 23 or tonumber(om) > 59 then return nil end
        offset = (tonumber(oh) * 60 + tonumber(om)) * 60 * (sign == "+" and 1 or -1)
    end
    local last = y - 1
    local total = 365 * (y - 1970) + math.floor(last / 4) - math.floor(1969 / 4)
        - math.floor(last / 100) + math.floor(1969 / 100) + math.floor(last / 400) - math.floor(1969 / 400)
    for month = 1, mo - 1 do total = total + days[month] end
    return ((total + d - 1) * 24 + h) * 3600 + mi * 60 + s - offset
end

function M.duration(at, now)
    if not finite(at) then return "重置时间未知" end
    local minutes = math.ceil((at - now) / 60)
    if minutes <= 0 then return "已到重置时间，待查询" end
    if minutes >= 1440 then return string.format("%d天%d小时", math.floor(minutes / 1440), math.floor(minutes % 1440 / 60)) end
    if minutes >= 60 then return string.format("%d小时%d分", math.floor(minutes / 60), minutes % 60) end
    return string.format("%d分", minutes)
end

local function text(value, fallback)
    if type(value) ~= "string" then return fallback end
    return value:gsub("[%c]", " "):sub(1, 100)
end

function M.entry(raw, now)
    if type(raw) ~= "table" or raw.status ~= "ready" or type(raw.metrics) ~= "table" then return nil end
    local metrics = {}
    for i, metric in ipairs(raw.metrics) do
        if i > 8 then break end
        if type(metric) == "table" and finite(metric.percent) and metric.percent >= 0 then
            metrics[#metrics + 1] = {
                label = text(metric.label, "额度"), percent = metric.percent,
                reset = M.epoch(metric.reset_at), window = finite(metric.window_secs) and metric.window_secs or nil,
            }
        end
    end
    if #metrics == 0 then return nil end
    local expiries, seen = {}, {}
    local credits = raw.id == "openai" and type(raw.reset_credits) == "table" and raw.reset_credits.credits
    if type(credits) == "table" then
        for i, credit in ipairs(credits) do
            if i > 32 then break end
            local expiry = type(credit) == "table" and M.epoch(credit.expires_at)
            if expiry and not seen[expiry] then expiries[#expiries + 1] = expiry; seen[expiry] = true end
        end
        table.sort(expiries)
    end
    return { metrics = metrics, fetched = M.epoch(raw.fetched_at) or now,
        manualResets = raw.id == "openai" and type(raw.reset_credits) == "table" and count(raw.reset_credits.available) or nil,
        manualExpiries = #expiries > 0 and expiries or nil,
        plan = text(raw.plan, ""), stale = raw.stale == true or (type(raw.error) == "string" and raw.error ~= "") }
end

function M.merge(previous, report, now)
    if type(report) ~= "table" or report.schema_version ~= 1 or type(report.entries) ~= "table" then return nil end
    local result = { providers = {}, errors = {}, checked = now }
    for _, id in ipairs(M.ids) do
        local found
        for _, raw in ipairs(report.entries) do
            if type(raw) == "table" and raw.id == id then found = raw; break end
        end
        local entry = M.entry(found, now)
        if entry then
            result.providers[id] = entry
            if entry.stale then result.errors[id] = "CLI 返回缓存数据" end
        else
            result.providers[id] = previous and previous.providers and previous.providers[id] or nil
            result.errors[id] = found and "订阅查询失败，请检查 CLI" or "CLI 未返回此订阅"
        end
    end
    return result
end

function M.restore(value)
    if type(value) ~= "table" or value.version ~= 1 or type(value.providers) ~= "table" then return {} end
    local providers = {}
    for _, id in ipairs(M.ids) do
        local entry = value.providers[id]
        if type(entry) == "table" and finite(entry.fetched) and type(entry.metrics) == "table" and #entry.metrics <= 8 then
            local valid = #entry.metrics > 0
            for _, metric in ipairs(entry.metrics) do
                if type(metric) ~= "table" or not finite(metric.percent) or metric.percent < 0
                    or type(metric.label) ~= "string" or #metric.label > 100
                    or (metric.reset ~= nil and not finite(metric.reset))
                    or (metric.window ~= nil and not finite(metric.window)) then valid = false end
            end
            if valid then
                local expiries = {}
                if id == "openai" and type(entry.manualExpiries) == "table" then
                    for i, expiry in ipairs(entry.manualExpiries) do
                        if i > 32 then break end
                        if finite(expiry) and expiry >= 0 then expiries[#expiries + 1] = expiry end
                    end
                end
                providers[id] = { metrics = entry.metrics, fetched = entry.fetched, plan = text(entry.plan, ""), stale = true,
                    manualResets = id == "openai" and count(entry.manualResets) or nil,
                    manualExpiries = #expiries > 0 and expiries or nil }
            end
        end
    end
    return providers
end

function M.request()
    local old = tonumber(noctalia.state.get("refresh")) or 0
    noctalia.state.set("refresh", old + 1)
end

function M.health(snapshot, heartbeat, now)
    if type(heartbeat) ~= "number" or now - heartbeat > 60 or now < heartbeat - 30 then
        return "刷新服务无响应；请在设置中重新启用本插件"
    end
    if snapshot and snapshot.error then return snapshot.error end
    return nil
end

return M
