---@class process
---@field pid integer
---@field stdout buffer
---@field stdin buffer
---@field stderr buffer
local process = {}
process.__index = process

local sys = require("syscalls")

process.SIGNAL_TERMINATE = "terminate"
process.SIGNAL_USER1 = "user1"
process.SIGNAL_USER2 = "user2"

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

-- Spawns a new process. cmd is the command
-- which will be mapped to a file path
-- using io.searchpath.
-- ... is all the extra arguments to pass through.
-- Not traced, default ring, default files,
-- same env as parent.
function process.exec(cmd, ...)
    cmd = io.searchpath(cmd)
    return process.spawn(cmd, {
        args = {...},
    })
end

function process.spawn(init, conf)
    conf = conf or {}
    local args = conf.args or {}
    local env = conf.env or os.getenvs()
    if conf.copyEnv then
        for k, v in pairs(os.getenvs()) do
            env[k] = v
        end
    end
    local traced = conf.traced
    local ring = conf.ring
    local cmdline = conf.cmdline
    local files = conf.files or {}
    files[0] = files[0] or io.stdout
    files[1] = files[1] or io.stdin
    files[2] = files[2] or io.stderr

    local fdMap = {}
    for fd, file in pairs(files) do
        fdMap[fd] = file:unwrap()
    end
    local pid, err = sys.pspawn(init, {
        ring = ring,
        cmdline = cmdline,
        args = args,
        env = env,
        traced = traced,
        fdMap = fdMap,
    })
    if not pid then return nil, err end
    return setmetatable({
        pid = pid,
        stdout = files[0],
        stdin = files[1],
        stderr = files[2],
    }, process)
end

function process:status()
    return assert(sys.pinfo(self.pid)).status
end

function process:kill()
    self:raise(process.SIGNAL_TERMINATE, assert(sys.pself()))
    -- errors are silenced
    self:wait()
    self:forceKill()
end

function process:wait()
    return sys.pawait(self.pid)
end

function process:waitToDie()
    return sys.pwait(self.pid)
end

function process:forceKill()
    return sys.pexit(self.pid)
end

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
