local model = require("./model.luau")
local dir = noctalia.pluginDataDir()
local cachePath = dir and dir .. "/last-success.json"
local snapshot = { providers = {}, errors = {}, busy = false }
local running = false
local serial, started, nextDue, lastTick = 0, -100, 0, 0

local function now() return noctalia.nowMs() / 1000 end
local function publish() noctalia.state.set("snapshot", snapshot) end

local function save()
    local encoded = noctalia.json.encode({ version = 1, providers = snapshot.providers })
    if not cachePath or not encoded then snapshot.cacheError = "成功数据缓存不可写"; return end
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
    started, nextDue = time, time + 300
    if not dir then finish("无法创建插件数据目录"); return end
    serial = serial + 1
    local run = serial
    running, snapshot.busy = true, true
    publish()
    -- flock survives VM reloads; timeout bounds CLI lifetime even if its callback is lost.
    local accepted = noctalia.runAsync({ "flock", "-n", "-E", "75", dir .. "/query.lock",
        "timeout", "-k", "2s", "30s", "ai-usagebar", "usage", "--json" }, function(result)
        if serial ~= run then return end
        if type(result) ~= "table" then finish("CLI 未返回结果"); return end
        if result.timedOut or result.exitCode == 124 or result.exitCode == 137 then finish("CLI 查询超时（30秒）"); return end
        if result.exitCode == 75 then nextDue = now() + 15; finish("上一次 CLI 查询尚未结束，稍后自动重试"); return end
        if result.exitCode ~= 0 then finish("CLI 查询失败，退出码 " .. tostring(result.exitCode)); return end
        if result.stdoutTruncated then finish("CLI 输出被截断"); return end
        local decoded = noctalia.json.decode(result.stdout or "")
        local merged = model.merge(snapshot, decoded, now())
        if not merged then finish("CLI JSON 无效或版本不兼容"); return end
        snapshot.providers, snapshot.errors, snapshot.checked = merged.providers, merged.errors, merged.checked
        save()
        finish(nil)
    end, 35000)
    if not accepted then finish("无法启动 CLI 查询"); return end
end

function update()
    local time = now()
    noctalia.state.set("heartbeat", time)
    if running and (time - started > 45 or time < started - 30) then
        serial = serial + 1
        finish("查询回调失效，稍后自动重试")
        nextDue = time + 15
        lastTick = time
    end
    local resumed = lastTick > 0 and (time - lastTick > 45 or time < lastTick - 30)
    lastTick = time
    if not running and (time >= nextDue or resumed) then refresh() end
end

function onIpc(event)
    if event == "refresh" then refresh() end
    if event == "status" then
        noctalia.log("status " .. (noctalia.json.encode(snapshot) or "{}"))
    end
end

noctalia.state.watch("refresh", function() refresh() end)
if cachePath then
    local info = noctalia.fileInfo(cachePath)
    if info and info.size <= 65536 then
        local raw = noctalia.readFile(cachePath)
        if raw then snapshot.providers = model.restore(noctalia.json.decode(raw)) end
    end
end
publish()
noctalia.setUpdateInterval(15000)
update()
