local model = require("./model.luau")
local dir = noctalia.pluginDataDir()
local cachePath = dir and dir .. "/last-success.json"
local snapshot = { providers = {}, errors = {}, busy = false }
local running = false
local serial, started, nextDue, lastTick = 0, -100, 0, 0
local watchdogSeconds = 45

local function now() return noctalia.nowMs() / 1000 end
local function publish() noctalia.state.set("snapshot", snapshot) end

local function save()
    local providers = {}
    for id, entry in pairs(snapshot.providers) do if entry.hasData then providers[id] = entry end end
    local encoded = noctalia.json.encode({ version = 2, providers = providers, order = snapshot.order,
        primary = snapshot.primary, preferences = snapshot.preferences })
    if not cachePath or not encoded or #encoded > 2097152 then snapshot.cacheError = "成功数据缓存不可写或过大"; return end
    local ok = noctalia.writeFile(cachePath .. ".tmp", encoded)
    if ok then ok = noctalia.renameFile(cachePath .. ".tmp", cachePath) end
    snapshot.cacheError = not ok and "成功数据缓存不可写" or nil
end

local function finish(errorText)
    running = false
    snapshot.busy = false
    snapshot.error = errorText
    publish()
end

local function refresh()
    local time = now()
    if running or (time >= started and time - started < 5) then return end
    started, nextDue = time, time + model.refreshSeconds()
    local timeoutSeconds = model.settingInt("timeout_seconds", 30, 5, 55)
    watchdogSeconds = timeoutSeconds + 15
    if not dir then finish("无法创建插件数据目录"); return end
    serial = serial + 1
    local run = serial
    running, snapshot.busy = true, true
    publish()
    -- flock survives VM reloads; timeout bounds CLI lifetime even if its callback is lost.
    local accepted = noctalia.runAsync({ "flock", "-n", "-E", "75", dir .. "/query.lock",
        "timeout", "-k", "2s", tostring(timeoutSeconds) .. "s", "ai-usagebar", "usage", "--json" }, function(result)
        if serial ~= run then return end
        if type(result) ~= "table" then finish("CLI 未返回结果"); return end
        if result.timedOut or result.exitCode == 124 or result.exitCode == 137 then
            finish("CLI 查询超时（" .. timeoutSeconds .. "秒）"); return
        end
        if result.exitCode == 75 then nextDue = now() + 15; finish("上一次 CLI 查询尚未结束，稍后自动重试"); return end
        if result.exitCode ~= 0 then finish("CLI 查询失败，退出码 " .. tostring(result.exitCode)); return end
        if result.stdoutTruncated then finish("CLI 输出被截断"); return end
        local decoded = noctalia.json.decode(result.stdout or "")
        local merged = model.merge(snapshot, decoded, now())
        if not merged then finish("CLI JSON 无效或版本不兼容"); return end
        snapshot.providers, snapshot.errors, snapshot.checked = merged.providers, merged.errors, merged.checked
        snapshot.order, snapshot.primary = merged.order, merged.primary
        save()
        finish(nil)
    end, (timeoutSeconds + 5) * 1000)
    if not accepted then finish("无法启动 CLI 查询"); return end
end

function update()
    local time = now()
    noctalia.state.set("heartbeat", time)
    if running and (time - started > watchdogSeconds or time < started - 30) then
        serial = serial + 1
        finish("查询回调失效，稍后自动重试")
        nextDue = time + 15
        lastTick = time
    end
    local resumed = lastTick > 0 and (time - lastTick > 45 or time < lastTick - 30)
    lastTick = time
    if not running and (time >= nextDue or resumed) then refresh() end
end

function onConfigChanged()
    nextDue = started + model.refreshSeconds()
    update()
end

function onIpc(event)
    if event == "refresh" then refresh() end
    if event == "status" then
        noctalia.log("status " .. (noctalia.json.encode(snapshot) or "{}"))
    end
end

noctalia.state.watch("refresh", function() refresh() end)
noctalia.state.watch("display_preferences", function(value)
    snapshot.preferences = model.preferences(value)
    save()
    publish()
end)
if cachePath then
    local info = noctalia.fileInfo(cachePath)
    if info and info.size <= 2097152 then
        local raw = noctalia.readFile(cachePath)
        local cached = raw and noctalia.json.decode(raw)
        if type(cached) == "table" then
            snapshot.providers = model.restore(cached)
            snapshot.order = type(cached.order) == "table" and cached.order or nil
            snapshot.primary = type(cached.primary) == "string" and cached.primary or nil
            snapshot.preferences = model.preferences(cached.preferences)
        end
    end
end
publish()
noctalia.setUpdateInterval(15000)
update()
