---@class process
---@field pid integer
---@field stdout buffer
---@field stdin buffer
---@field stderr buffer
local process = {}
process.__index = process

local sys = require("syscalls")

function process.self()
    return setmetatable({
        pid = assert(sys.pself()),
        stdout = io.stdout,
        stdin = io.stdin,
        stderr = io.stderr,
    }, process)
end

---@param pid integer
--- The stdout, stdin and stderr are empty tmpfiles.
function process.wrap(pid)
    return setmetatable({
        pid = pid,
        stdout = assert(io.tmpfile()),
        stdin = assert(io.tmpfile()),
        stderr = assert(io.tmpfile()),
    }, process)
end

function process:status()
    return sys.pstatus(self.pid)
end

function process:forceKill()
    return sys.pexit(self.pid)
end

process.SIGNAL_TERMINATE = "terminate"
process.SIGNAL_USER1 = "user1"
process.SIGNAL_USER2 = "user2"

function process:raise(signal, ...)
    return sys.psignal(self.pid, signal, ...)
end

---@return integer[]
function process.allPids()
    local t = {}
    local pid
    while true do
        local npid = sys.pnext(pid)
        if npid == nil then break end
        table.insert(t, npid)
        pid = npid
    end
    return t
end

return process
