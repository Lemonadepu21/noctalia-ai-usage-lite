local M = {}

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
    value = value:gsub("[%c]", " ")
    local cut = math.min(#value, 100)
    while cut > 0 and value:byte(cut + 1) and value:byte(cut + 1) >= 128 and value:byte(cut + 1) < 192 do cut = cut - 1 end
    return value:sub(1, cut)
end

local function validId(id)
    return type(id) == "string" and #id > 0 and #id <= 160 and not id:find("[%c]")
end

local function metadata(raw)
    local name = text(raw.display_name or raw.name, raw.id)
    return { name = name ~= "" and name or raw.id,
        brand = text(raw.brand, raw.id:match("^([^@]+)")), plan = text(raw.plan, "") }
end

local function metric(raw, cached)
    if type(raw) ~= "table" or not finite(raw.percent) or raw.percent < 0 then return nil end
    if raw.headline == "value" and (type(raw.value) ~= "string" or raw.value == "") then return nil end
    return { type = "metric", label = text(raw.label, "额度"), percent = raw.percent,
        headline = raw.headline == "value" and "value" or "percent", value = text(raw.value, ""),
        detail = text(raw.detail, ""),
        reset = cached and (finite(raw.reset) and raw.reset or nil) or M.epoch(raw.reset_at),
        window = cached and (finite(raw.window) and raw.window or nil)
            or (finite(raw.window_secs) and raw.window_secs or nil) }
end

function M.entry(raw, now, cached)
    if type(raw) ~= "table" or not validId(raw.id) or raw.status ~= "ready" then return nil end
    local entry = metadata(raw)
    entry.metrics, entry.sections = {}, {}
    for i, section in ipairs(type(raw.sections) == "table" and raw.sections or {}) do
        if i > 64 then break end
        if type(section) == "table" then
            local normalized
            if section.type == "metric" then
                normalized = metric(section, cached)
                if normalized then entry.metrics[#entry.metrics + 1] = normalized end
            elseif section.type == "text" and type(section.value) == "string" then
                normalized = { type = "text", label = text(section.label, ""), value = text(section.value, "") }
            elseif section.type == "block" and type(section.body) == "table" then
                local body = {}
                for j, line in ipairs(section.body) do
                    if j > 16 then break end
                    if type(line) == "string" then body[#body + 1] = text(line, "") end
                end
                if #body > 0 then normalized = { type = "block", label = text(section.label, ""), body = body } end
            end
            if normalized then entry.sections[#entry.sections + 1] = normalized end
        end
    end
    -- sections preserves balance and text rows that the metrics convenience view omits.
    if #entry.sections == 0 then
        for i, item in ipairs(type(raw.metrics) == "table" and raw.metrics or {}) do
            if i > 32 then break end
            local normalized = metric(item, cached)
            if normalized then
                entry.metrics[#entry.metrics + 1] = normalized
                entry.sections[#entry.sections + 1] = normalized
            end
        end
    end
    if #entry.sections == 0 then return nil end
    local occurrences = {}
    for _, section in ipairs(entry.sections) do
        local base = section.type .. ":" .. section.label
        occurrences[base] = (occurrences[base] or 0) + 1
        section.key = base .. ":" .. occurrences[base]
    end
    local inventory = type(raw.reset_credits) == "table" and raw.reset_credits or {}
    local expiries, seen = {}, {}
    local credits = cached and raw.manualExpiries or inventory.credits
    for i, credit in ipairs(type(credits) == "table" and credits or {}) do
        if i > 32 then break end
        local expiry = cached and (finite(credit) and credit >= 0 and credit or nil)
            or (type(credit) == "table" and M.epoch(credit.expires_at))
        if expiry and not seen[expiry] then expiries[#expiries + 1] = expiry; seen[expiry] = true end
    end
    table.sort(expiries)
    entry.manualResets = count(cached and raw.manualResets or inventory.available)
    entry.manualExpiries = #expiries > 0 and expiries or nil
    entry.fetched = cached and raw.fetched or M.epoch(raw.fetched_at) or now
    entry.hasData = true
    entry.stale = cached or raw.stale == true or (type(raw.error) == "string" and raw.error ~= "")
    return entry
end

function M.merge(previous, report, now)
    if type(report) ~= "table" or report.schema_version ~= 1 or type(report.entries) ~= "table" then return nil end
    local result = { providers = {}, order = {}, errors = {}, checked = now,
        primary = validId(report.primary) and report.primary or nil,
        preferences = previous and previous.preferences }
    for i, raw in ipairs(report.entries) do
        if i > 128 then break end
        if type(raw) == "table" and validId(raw.id) and not result.providers[raw.id] then
            local id = raw.id
            local entry = M.entry(raw, now)
            if entry then
                if entry.stale then result.errors[id] = "CLI 返回缓存数据" end
            else
                entry = previous and previous.providers and previous.providers[id] or metadata(raw)
                entry.metrics, entry.sections = entry.metrics or {}, entry.sections or {}
                result.errors[id] = "此账户未返回可用数据，请检查 CLI 配置或认证"
            end
            result.providers[id] = entry
            result.order[#result.order + 1] = id
        end
    end
    return result
end

function M.restore(value)
    if type(value) ~= "table" or (value.version ~= 1 and value.version ~= 2) or type(value.providers) ~= "table" then return {} end
    local providers, size = {}, 0
    for id, saved in pairs(value.providers) do
        size = size + 1; if size > 128 then break end
        if validId(id) and type(saved) == "table" and finite(saved.fetched) then
            local raw = { id = id, name = saved.name or (id == "openai" and "Codex" or id == "opencode-go" and "OpenCode Go" or id),
                brand = saved.brand, plan = saved.plan, status = "ready", fetched = saved.fetched,
                metrics = saved.metrics, sections = saved.sections,
                manualResets = saved.manualResets, manualExpiries = saved.manualExpiries }
            providers[id] = M.entry(raw, saved.fetched, true)
        end
    end
    return providers
end

function M.ids(snapshot)
    local ids, seen = {}, {}
    local providers = snapshot.providers or {}
    for _, id in ipairs(snapshot.order or {}) do
        if providers[id] and providers[id].hasData and not seen[id] then ids[#ids + 1] = id; seen[id] = true end
    end
    local extra = {}
    for id, entry in pairs(providers) do if entry.hasData and not seen[id] then extra[#extra + 1] = id end end
    table.sort(extra)
    for _, id in ipairs(extra) do ids[#ids + 1] = id end
    return ids
end

function M.preferences(value)
    local prefs = { sections = {} }
    if type(value) ~= "table" then return prefs end
    if type(value.tabs) == "table" then
        prefs.tabs = {}
        local seen = {}
        for i, id in ipairs(value.tabs) do
            if i > 128 then break end
            if validId(id) and not seen[id] then prefs.tabs[#prefs.tabs + 1] = id; seen[id] = true end
        end
    end
    local size = 0
    for id, flags in pairs(type(value.sections) == "table" and value.sections or {}) do
        size = size + 1; if size > 128 then break end
        if validId(id) and type(flags) == "table" then
            local cleaned, countFlags = {}, 0
            for key, enabled in pairs(flags) do
                countFlags = countFlags + 1; if countFlags > 128 then break end
                if validId(key) and type(enabled) == "boolean" then cleaned[key] = enabled end
            end
            prefs.sections[id] = cleaned
        end
    end
    return prefs
end

function M.tabIds(snapshot)
    local ids = M.ids(snapshot)
    local configured = snapshot.preferences and snapshot.preferences.tabs
    if not configured then return ids end
    local shown, wanted = {}, {}
    for _, id in ipairs(configured) do wanted[id] = true end
    for _, id in ipairs(ids) do if wanted[id] then shown[#shown + 1] = id end end
    return shown
end

function M.shown(entry, prefs, id, section)
    local flags = prefs and prefs.sections and prefs.sections[id]
    if flags and flags[section.key] ~= nil then return flags[section.key] end
    if section.key == "manual-resets" then return true end
    -- Codex's supplementary Credits block is not a separate configured API account.
    return entry.brand ~= "openai" or (section.type == "metric" and section.headline == "percent")
end

function M.sections(entry, prefs, id)
    local sections = {}
    for _, section in ipairs(entry and entry.sections or {}) do
        if not (entry.manualResets ~= nil and section.label == "Reset credits")
            and M.shown(entry, prefs, id, section) then sections[#sections + 1] = section end
    end
    return sections
end

function M.barId(snapshot, requested)
    local providers = snapshot.providers or {}
    if type(requested) == "string" and requested ~= "" then
        return providers[requested] and providers[requested].hasData and requested or nil
    end
    if providers.openai and providers.openai.hasData then return "openai" end
    if type(snapshot.primary) == "string" and providers[snapshot.primary] and providers[snapshot.primary].hasData then return snapshot.primary end
    return M.ids(snapshot)[1]
end

function M.glyph(entry)
    if entry and entry.brand == "openai" then return "brand-openai" end
    if entry and entry.brand == "opencode-go" then return "code" end
    return "brain"
end

function M.barRows(entry, prefs, id)
    local rows = {}
    for _, section in ipairs(M.sections(entry, prefs, id)) do
        if section.type == "metric" or section.type == "text" then rows[#rows + 1] = section
        elseif section.type == "block" and #rows == 0 then
            rows[1] = { type = "text", label = section.label, value = section.body[1] }
        end
        if #rows >= 2 then break end
    end
    return rows
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
