-- SystemK, like systemd but even worse
-- TODO: restart services that crash, domain server and CLI tool

---@class SystemK.Record
---@field init string
---@field args string[]
---@field env {[string]: string}
---@field dependencies string[]
---@field priority number
---@field step "init"|"shell"|"services"|"postservices"

local lon = require("lon")
local process = require("process")

-- Boot-up system
-- Run all boot info
-- Run all services
-- init -> shell -> services -> postservices

local stepOrder = {"init", "shell", "services", "postservices"}

local function allServices()
    return io.list("/etc/systemk") or {}
end

local function fetchServiceInfo(service)
    local f = assert(io.open("/etc/systemk/" .. service))
    local code = f:read("a")
    f:close()
    ---@type SystemK.Record
    local info = lon.decode(code)
    info.args = info.args or {}
    info.env = info.env or {}
    info.dependencies = info.dependencies or {}
    info.priority = info.priority or 100
    info.step = info.step or "services"
    return info
end

local records = {}

local serviceList = allServices()
for _, service in ipairs(serviceList) do
    records[service] = fetchServiceInfo(service)
end

table.sort(serviceList, function(a, b)
    return records[a].priority > records[b].priority
end)

local servicesRan = {}

local function runService(service)
    if servicesRan[service] then return end
    servicesRan[service] = true
    ---@type SystemK.Record
    local record = records[service]
    for _, dep in ipairs(record.dependencies) do
        runService(dep)
    end

    assert(process.spawn(record.init, {
        args = record.args,
        env = record.env,
    }))
end

local function runStep(step)
    for _, service in ipairs(serviceList) do
        if records[service].step == step then
            runService(service)
        end
    end
end

for _, step in ipairs(stepOrder) do
    runStep(step)
end

while true do
    coroutine.yield()
end
