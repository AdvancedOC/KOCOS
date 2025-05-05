---@class KOCOS.Lock
---@field locked boolean
local lock = {}
lock.__index = lock

function lock.create()
    return setmetatable({locked = false}, lock)
end

function lock:tryLock()
    if self.locked then return false end
    self.locked = true
    return true
end

---@param timeout integer
function lock:lock(timeout)
    local deadline = computer.uptime() + timeout
    while self.locked do
        if computer.uptime() > deadline then
            error("timeout")
        end
        KOCOS.yield()
    end
    self.locked = true
end

function lock:unlock()
    self.locked = false
end

KOCOS.lock = lock
