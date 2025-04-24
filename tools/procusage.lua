if arg[1] == "-w" then
    while true do coroutine.yield() end
end

-- Test process usage
assert(_KVERSION, "needs to run in KOCOS")

local process = require("process")
local us = process.self()

local function freeMemory()
    local err, info = syscall("cstat")
    assert(info, err)
    return info.memFree
end

local memoryInitial = freeMemory()

local count = 0
while true do
    local _, err = process.exec("luart", "tools/procusage.lua", "-w")
    if err then
        print(err)
        local now = freeMemory()
        local usage = memoryInitial - now
        print(string.memformat(usage / count))
        us:forceKill()
    end
    count = count + 1
    local now = freeMemory()
    local usage = memoryInitial - now
    print(count, string.memformat(usage / count))
end
